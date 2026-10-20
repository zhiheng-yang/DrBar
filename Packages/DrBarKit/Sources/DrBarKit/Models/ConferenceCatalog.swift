import Foundation

/// The conference deadlines from ccfddl, parsed and trimmed to what the app shows.
///
/// Stored as `deadlines.json` and read at launch, so the YAML is parsed only after a download.
/// Only dates published for an edition are kept; nothing is predicted.
public struct ConferenceCatalog: Codable, Hashable, Sendable {
    /// Bumped whenever parsing changes, so an old `deadlines.json` is rebuilt from the cached YAML.
    public static let currentFormatVersion = 5

    public var formatVersion: Int
    public var series: [ConferenceSeries]

    public init(series: [ConferenceSeries]) {
        self.formatVersion = Self.currentFormatVersion
        self.series = series
    }

    public static let empty = ConferenceCatalog(series: [])

    public func series(withKey key: String) -> ConferenceSeries? {
        series.first { $0.id == key }
    }

    public func edition(series key: String, year: Int) -> (ConferenceSeries, ConferenceEdition)? {
        guard let s = series(withKey: key), let e = s.editions.first(where: { $0.year == year }) else { return nil }
        return (s, e)
    }

    public func edition(id: String) -> (ConferenceSeries, ConferenceEdition)? {
        for s in series {
            if let e = s.editions.first(where: { $0.id == id }) { return (s, e) }
        }
        return nil
    }

    /// The catalog with each series' acceptance rates from `rates`, by its key, or else by its
    /// title where only one series has it; those without any have none.
    public func withAcceptance(_ rates: [AcceptanceRates]) -> ConferenceCatalog {
        let byKey = Dictionary(
            rates.compactMap { r in r.seriesKey.map { ($0, r.years) } }, uniquingKeysWith: { a, _ in a })
        let titles = Dictionary(grouping: series, by: { $0.title.lowercased() })
        let byTitle = Dictionary(
            rates.filter { $0.seriesKey == nil }.compactMap { r -> (String, [AcceptanceRate])? in
                let matches = titles[r.title.lowercased()] ?? []
                return matches.count == 1 ? (matches[0].id, r.years) : nil
            }, uniquingKeysWith: { a, _ in a })
        var catalog = self
        for index in catalog.series.indices {
            let id = catalog.series[index].id
            catalog.series[index].acceptance = (byKey[id] ?? byTitle[id] ?? []).sorted { $0.year < $1.year }
        }
        return catalog
    }
}

/// How many papers a conference took of those submitted, one year, as ccfddl collects it.
public struct AcceptanceRate: Codable, Hashable, Sendable {
    public var year: Int
    /// From 0 to 1.
    public var rate: Double
    public var submitted: Int?
    public var accepted: Int?

    public init(year: Int, rate: Double, submitted: Int? = nil, accepted: Int? = nil) {
        self.year = year
        self.rate = rate
        self.submitted = submitted
        self.accepted = accepted
    }
}

/// The acceptance rates of one conference series, as read before they are matched to it.
public struct AcceptanceRates: Hashable, Sendable {
    /// ccfddl's `conference_key`, when it gives one.
    public var seriesKey: String?
    public var title: String
    public var years: [AcceptanceRate]

    public init(seriesKey: String?, title: String, years: [AcceptanceRate]) {
        self.seriesKey = seriesKey
        self.title = title
        self.years = years
    }
}

/// A conference series such as CVPR. Its `id` is ccfddl's `conference_key`, e.g. `AI/cvpr`.
public struct ConferenceSeries: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    /// CCF category: AI, CG, DB, DS, NW, SC, SE, CT, HI or MX.
    public var category: String
    /// CCF rank: A, B, C or N (not ranked).
    public var ccfRank: String?
    /// The CORE rank (A*, A, B, C) and the TH-CPL rank of Tsinghua's list (A, B), or N.
    public var coreRank: String?
    public var thcplRank: String?
    /// Its key on DBLP (`conf/cvpr`), where its papers are listed.
    public var dblp: String?
    /// Editions, oldest first.
    public var editions: [ConferenceEdition]
    /// How many papers it took in past years, oldest first.
    public var acceptance: [AcceptanceRate]

    public init(
        id: String, title: String, description: String, category: String, ccfRank: String?,
        coreRank: String? = nil, thcplRank: String? = nil, dblp: String? = nil, editions: [ConferenceEdition],
        acceptance: [AcceptanceRate] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.ccfRank = ccfRank
        self.coreRank = coreRank
        self.thcplRank = thcplRank
        self.dblp = dblp
        self.editions = editions
        self.acceptance = acceptance
    }

    /// The latest year's acceptance rate.
    public var latestAcceptance: AcceptanceRate? {
        acceptance.last
    }

    /// The series' page on DBLP.
    public var dblpURL: URL? {
        dblp.flatMap { URL(string: "https://dblp.org/db/conf/\($0)/") }
    }

    /// The CCF rank worth showing; `N` (not ranked) is hidden.
    public var displayRank: String? {
        Self.shown(ccfRank)
    }

    public var displayCoreRank: String? {
        Self.shown(coreRank)
    }

    public var displayThcplRank: String? {
        Self.shown(thcplRank)
    }

    private static func shown(_ rank: String?) -> String? {
        guard let rank, rank != "N", !rank.isEmpty else { return nil }
        return rank
    }
}

/// One year of a conference, such as CVPR 2027.
public struct ConferenceEdition: Codable, Hashable, Sendable, Identifiable {
    /// ccfddl's edition id, e.g. `cvpr27`.
    public var id: String
    public var year: Int
    public var link: String
    /// The time zone exactly as ccfddl writes it.
    public var timeZone: String
    /// When and where the conference takes place, as written (may be `TBD`).
    public var date: String?
    public var place: String?
    /// `date` read as days, when it follows one of the usual forms.
    public var meeting: MeetingDates?
    public var rounds: [ConferenceRound]
    /// The paper deadline of the previous edition, shown in grey "for reference" only.
    /// It never feeds bars, reminders or planning.
    public var previous: PreviousEdition?

    public init(
        id: String, year: Int, link: String, timeZone: String, date: String?, place: String?,
        meeting: MeetingDates? = nil, rounds: [ConferenceRound], previous: PreviousEdition?
    ) {
        self.id = id
        self.year = year
        self.link = link
        self.timeZone = timeZone
        self.date = date
        self.place = place
        self.meeting = meeting
        self.rounds = rounds
        self.previous = previous
    }

    public var url: URL? {
        URL(string: link.trimmingCharacters(in: .whitespaces))
    }

    /// The previous edition when it was the year before, as "last year" says; a conference held
    /// every other year has none.
    public var lastYear: PreviousEdition? {
        previous.flatMap { $0.year == year - 1 ? $0 : nil }
    }
}

/// One submission round of an edition. Most editions have a single round.
public struct ConferenceRound: Codable, Hashable, Sendable, Identifiable {
    /// Stable within the edition: the comment when there is one (so inserting a round upstream
    /// does not shift ids), otherwise `#n`. Repeated comments get `#n` appended.
    public var id: String
    /// Position in the edition's timeline, starting at 0.
    public var index: Int
    public var comment: String?
    public var abstract: DeadlineValue?
    public var paper: DeadlineValue?
    public var rebuttal: DeadlineValue?
    public var decision: DeadlineValue?

    public init(
        id: String, index: Int, comment: String?, abstract: DeadlineValue?, paper: DeadlineValue?,
        rebuttal: DeadlineValue?, decision: DeadlineValue?
    ) {
        self.id = id
        self.index = index
        self.comment = comment
        self.abstract = abstract
        self.paper = paper
        self.rebuttal = rebuttal
        self.decision = decision
    }

    public func value(_ kind: DeadlineKind) -> DeadlineValue? {
        switch kind {
        case .abstract: abstract
        case .paper: paper
        case .rebuttal: rebuttal
        case .decision: decision
        }
    }

    /// When submissions to it close: its paper deadline, or its abstract while only that is known.
    public var closingDate: Date? {
        paper?.date ?? abstract?.date
    }
}

/// The kinds of dates an edition can list.
extension ConferenceEdition {
    /// The round a paper follows: the one fixed for it while it is there; otherwise the next one to
    /// come, by its paper deadline or, while only that is known, its abstract, or one not announced
    /// yet after those that have passed; once all have passed, the last.
    public func round(id: String?, now: Date) -> ConferenceRound? {
        if let id, let fixed = rounds.first(where: { $0.id == id }) {
            return fixed
        }
        let dated = rounds.compactMap { round in round.closingDate.map { (round: round, date: $0) } }
        return dated.filter { $0.date > now }.min { $0.date < $1.date }?.round ?? pendingRound(now: now)
            ?? dated.max { $0.date < $1.date }?.round ?? rounds.first
    }

    /// The round to come once every round with a date has passed: the first after them, whose
    /// date is not announced yet, while the conference has yet to meet.
    public func pendingRound(now: Date) -> ConferenceRound? {
        guard !isOver(now: now), let last = rounds.lastIndex(where: { $0.closingDate != nil }),
            !rounds.contains(where: { ($0.closingDate ?? .distantPast) > now })
        else { return nil }
        return rounds[(last + 1)...].first
    }

    /// Whether the conference has met, by its last day, or without its days, by its year.
    public func isOver(now: Date) -> Bool {
        if let meeting {
            return meeting.end < Day(now)
        }
        return year < Calendar.gregorian(in: .gmt).component(.year, from: now)
    }

    /// The round whose paper deadline is nearest to `now`, the one a paper marked submitted then
    /// went to, a day early or a day late.
    public func round(nearest now: Date) -> ConferenceRound? {
        rounds.compactMap { round in round.paper?.date.map { (round, abs($0.timeIntervalSince(now))) } }
            .min { $0.1 < $1.1 }?.0
    }
}

public enum DeadlineKind: String, Codable, CaseIterable, Sendable {
    case abstract, paper, rebuttal, decision
}

/// A date as ccfddl writes it, plus the instant it stands for.
public struct DeadlineValue: Codable, Hashable, Sendable {
    /// The text from ccfddl, such as `2026-11-16 23:59:59` or `TBD`.
    public var raw: String
    /// `nil` when the date is not announced or its time zone is not recognized.
    public var date: Date?

    public init(raw: String, date: Date?) {
        self.raw = raw
        self.date = date
    }

    public var isAnnounced: Bool {
        raw.announcedText != nil
    }
}

extension String {
    /// The text without surrounding spaces, or `nil` when it is empty or `TBD`, ccfddl's word for
    /// what is not known yet.
    public var announcedText: String? {
        let text = trimmingCharacters(in: .whitespaces)
        return text.isEmpty || text.uppercased() == "TBD" ? nil : text
    }
}

/// The previous edition's paper deadline, for reference.
public struct PreviousEdition: Codable, Hashable, Sendable {
    public var year: Int
    /// The raw paper deadline text, e.g. `2025-11-13 23:59:59`.
    public var paperDeadline: String

    public init(year: Int, paperDeadline: String) {
        self.year = year
        self.paperDeadline = paperDeadline
    }
}
