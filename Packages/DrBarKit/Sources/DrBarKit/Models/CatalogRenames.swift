import Foundation

/// What ccfddl knows by other names from one catalog to the next: conferences whose key moved with
/// their file, and rounds whose comment was written or rewritten, which ccfddl often does as it
/// moves the dates. What is kept by those names goes over to the new ones, lest a star or a target
/// stop matching, a ticked date come back, a fixed round be lost or a changed date go unannounced.
public struct CatalogRenames: Hashable, Sendable {
    /// The new key of each series whose key changed.
    var series: [String: String] = [:]
    /// By edition id, the new id of each round whose id changed.
    var rounds: [String: [String: String]] = [:]
    /// By edition id, the rounds that are gone while another round took their id.
    var gone: [String: Set<String>] = [:]

    public var isEmpty: Bool {
        series.isEmpty && rounds.isEmpty && gone.isEmpty
    }

    /// The key a series has now.
    public func series(_ key: String) -> String {
        series[key] ?? key
    }

    /// The new id of the round `id` of the edition with `editionID`, if it changed.
    public func round(_ id: String, ofEdition editionID: String) -> String? {
        rounds[editionID]?[id]
    }

    /// A deadline's id (`DeadlineItem.id`) with its round's new id; `nil` for a round that is gone,
    /// whose id now means another.
    public func deadlineID(_ id: String) -> String? {
        guard let (edition, kind, old) = DeadlineItem.parts(of: id) else { return id }
        if gone[edition]?.contains(old) == true { return nil }
        guard let round = round(old, ofEdition: edition) else { return id }
        return DeadlineItem.id(edition: edition, kind: kind, round: round)
    }
}

extension ConferenceCatalog {
    /// What `newer` knows by other names: a series gone from it by the key of the one that has its
    /// editions there, and the rounds of each edition as `roundIDs` finds them.
    public func renames(in newer: ConferenceCatalog) -> CatalogRenames {
        var renames = CatalogRenames()
        let keys = Set(newer.series.map(\.id))
        let owners = Dictionary(
            newer.series.flatMap { series in series.editions.map { ($0.id, series.id) } },
            uniquingKeysWith: { first, _ in first })
        for series in series where !keys.contains(series.id) {
            let moved = Set(series.editions.compactMap { owners[$0.id] })
            if moved.count == 1, let key = moved.first {
                renames.series[series.id] = key
            }
        }
        let editions = Dictionary(
            newer.series.flatMap(\.editions).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for edition in series.flatMap(\.editions) {
            guard let next = editions[edition.id] else { continue }
            let renamed = edition.roundIDs(in: next).filter { $0.key != $0.value }
            if !renamed.isEmpty {
                renames.rounds[edition.id] = renamed
            }
            let gone = Set(edition.rounds.map(\.id)).intersection(renamed.values).subtracting(renamed.keys)
            if !gone.isEmpty {
                renames.gone[edition.id] = gone
            }
        }
        return renames
    }
}

extension ConferenceEdition {
    /// Which round of `newer`, this edition as ccfddl lists it later, each of its rounds became: the
    /// one with the same comment; else one with the same paper deadline as written, or closing within
    /// a day of it; else the one in the same place, while the rounds found so far have all moved by
    /// as many places, or, with none found, while the edition has as many rounds as before.
    func roundIDs(in newer: ConferenceEdition) -> [String: String] {
        var pairs: [Int: Int] = [:]
        var taken = Set<Int>()
        func pair(_ old: Int, _ new: Int?) {
            guard let new, !taken.contains(new) else { return }
            pairs[old] = new
            taken.insert(new)
        }
        for (index, round) in rounds.enumerated() where round.comment == round.id {
            pair(index, newer.rounds.firstIndex { $0.id == round.id })
        }
        for (index, round) in rounds.enumerated() where pairs[index] == nil {
            guard let deadline = round.paper?.raw.announcedText else { continue }
            let match = newer.rounds.indices.first {
                !taken.contains($0) && newer.rounds[$0].paper?.raw.announcedText == deadline
            }
            pair(index, match)
        }
        for (index, round) in rounds.enumerated() where pairs[index] == nil {
            guard let closes = round.closingDate else { continue }
            let match = newer.rounds.indices.first { candidate in
                guard !taken.contains(candidate), let date = newer.rounds[candidate].closingDate else { return false }
                return abs(date.timeIntervalSince(closes)) < 86_400
            }
            pair(index, match)
        }
        let shifts = Set(pairs.map { $0.value - $0.key })
        if shifts.count == 1 || (shifts.isEmpty && rounds.count == newer.rounds.count) {
            let shift = shifts.first ?? 0
            for index in rounds.indices where pairs[index] == nil && newer.rounds.indices.contains(index + shift) {
                pair(index, index + shift)
            }
        }
        return Dictionary(
            pairs.map { (rounds[$0.key].id, newer.rounds[$0.value].id) }, uniquingKeysWith: { first, _ in first })
    }
}

extension UserData {
    /// Carries what is kept by the names of series and rounds over to their new names: the stars,
    /// what papers and items aim at, their ticked dates, the dates last seen and a series shown in
    /// the menu bar. Returns whether any changed.
    @discardableResult
    public mutating func follow(_ renames: CatalogRenames, in catalog: ConferenceCatalog) -> Bool {
        guard !renames.isEmpty else { return false }
        let before = self
        favoriteSeries = Set(favoriteSeries.map(renames.series))
        if case let .series(key)? = settings.menuBarSubject {
            settings.menuBarSubject = .series(renames.series(key))
        }
        updateEveryPaper { paper in
            guard var target = paper.target else { return }
            target.series = renames.series(target.series)
            if let round = target.round, let (_, edition) = catalog.edition(series: target.series, year: target.year),
                let renamed = renames.round(round, ofEdition: edition.id)
            {
                target.round = renamed
            }
            paper.target = target
            let ticks = paper.doneDeadlines.compactMap(renames.deadlineID)
            if ticks != paper.doneDeadlines {
                // In order, as ticking keeps them.
                paper.doneDeadlines = Set(ticks).sorted()
            }
        }
        var seen: [String: String] = [:]
        for (key, value) in lastSeen {
            guard let id = renames.deadlineID(key) else { continue }
            // What a round brings to its new id comes before anything left there.
            if id != key || seen[id] == nil {
                seen[id] = value
            }
        }
        lastSeen = seen
        return self != before
    }
}
