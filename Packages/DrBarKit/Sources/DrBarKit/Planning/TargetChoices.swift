import Foundation

/// What the Conferences page lists.
public struct DeadlineFilter: Hashable, Sendable {
    public enum Scope: Sendable {
        /// What `following` covers.
        case following
        /// Every series that passes the category, rank and search filters.
        case all
    }

    public var scope: Scope
    /// CCF categories to show in `.all`; empty shows every category.
    public var categories: Set<String>
    /// CCF ranks to show in `.all`; empty shows every rank.
    public var ranks: Set<String>
    /// CORE and TH-CPL ranks to show in `.all`, N for the unranked; empty shows every rank.
    public var coreRanks: Set<String>
    public var thcplRanks: Set<String>
    public var search: String
    /// Editions whose deadlines have all passed too, as ccfddl shows past conferences.
    public var includesPassed: Bool

    public init(
        scope: Scope = .following, categories: Set<String> = [], ranks: Set<String> = [],
        coreRanks: Set<String> = [], thcplRanks: Set<String> = [], search: String = "", includesPassed: Bool = false
    ) {
        self.scope = scope
        self.categories = categories
        self.ranks = ranks
        self.coreRanks = coreRanks
        self.thcplRanks = thcplRanks
        self.search = search
        self.includesPassed = includesPassed
    }

    public func matches(_ series: ConferenceSeries) -> Bool {
        if !categories.isEmpty, !categories.contains(series.category) { return false }
        if !ranks.isEmpty, !ranks.contains(series.ccfRank ?? "N") { return false }
        if !coreRanks.isEmpty, !coreRanks.contains(series.coreRank ?? "N") { return false }
        if !thcplRanks.isEmpty, !thcplRanks.contains(series.thcplRank ?? "N") { return false }
        return matchesSearch(series.title) || matchesSearch(series.description) || matchesSearch(series.id)
    }

    public func matchesSearch(_ text: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || text.localizedStandardContains(query)
    }
}

/// A deadline that the menu bar counts down to and reminders announce, once however many follow it.
public struct FollowedDeadline: Hashable, Sendable, Identifiable {
    public var deadline: PaperDeadline
    public var date: Date
    /// How the menu bar names it: the conference series (`CVPR`), else the paper's or the item's
    /// title.
    public var name: String
    /// What a reminder starts with: the edition and its round (`SIGMOD 2027 #4`), or the paper's or
    /// the item's title.
    public var title: String
    /// Whose it is: a paper's or an item's id, or a starred round's row; the menu bar shows the next
    /// of each.
    public var owner: String
    /// The one paper or item that has it open, where Mark as Done ticks it off.
    public var paperID: UUID?
    public var destination: Destination
    /// When the work towards it started (`Paper.startedAt`), the earliest for a deadline that
    /// several papers or items share. A conference followed on its own has none.
    public var start: Date?

    public var id: String {
        deadline.id
    }

    public init(
        deadline: PaperDeadline, date: Date, name: String, title: String, owner: String, paperID: UUID? = nil,
        destination: Destination, start: Date? = nil
    ) {
        self.deadline = deadline
        self.date = date
        self.name = name
        self.title = title
        self.owner = owner
        self.paperID = paperID
        self.destination = destination
        self.start = start
    }

    /// How much of its time is still ahead at `now`: 1 until its work started, 0 at the deadline.
    /// Without a start before the deadline, its time is the `fallback` before it.
    public func shareLeft(at now: Date, fallback: TimeInterval) -> Double {
        var span = fallback
        if let start, start < date {
            span = date.timeIntervalSince(start)
        }
        return min(max(date.timeIntervalSince(now) / span, 0), 1)
    }
}

/// An edition of a conference, as the Conferences page lists it to star it or for a paper to aim at.
public struct TargetChoice: Identifiable, Hashable, Sendable {
    public var target: Paper.Target
    /// "CVPR", the series' name.
    public var name: String
    /// The conference's full name.
    public var detail: String
    /// The CCF category, and the ranks of the CCF, CORE and TH-CPL lists, `nil` where not ranked.
    public var category: String
    public var rank: String?
    public var coreRank: String?
    public var thcplRank: String?
    /// Where and when the conference meets, as far as announced: the city, and the flags of the
    /// countries of the whole place.
    public var place: String?
    public var flags: String
    public var meeting: MeetingDates?
    /// The next paper deadline of the edition, or its last one once all have passed; `nil` while
    /// none is announced. A round with only an abstract deadline counts with that.
    public var deadline: Date?
    /// The abstract registration of the same round, where it has one before its paper deadline.
    public var abstractDeadline: Date?
    /// As ccfddl writes it, for the exact times.
    public var timeZone: String
    /// Whether its deadline is a date, not announced, or written in a way that cannot be read.
    public var state: DeadlineRow.State
    public var hasPassed: Bool
    public var isStarred: Bool
    /// Which round the deadlines are of, where the edition has several.
    public var roundLabel: String?
    /// ccfddl's comment on that round, where it says more than its label.
    public var note: String?
    /// The conference's latest acceptance rate.
    public var acceptance: AcceptanceRate?
    /// The previous edition's paper deadline, for reference while this one's is not announced.
    public var lastYear: Day?

    public init(
        target: Paper.Target, name: String, detail: String, category: String, rank: String? = nil,
        coreRank: String? = nil, thcplRank: String? = nil, place: String? = nil, flags: String = "",
        meeting: MeetingDates? = nil,
        deadline: Date? = nil, abstractDeadline: Date? = nil, timeZone: String, state: DeadlineRow.State,
        hasPassed: Bool, isStarred: Bool, roundLabel: String? = nil, note: String? = nil,
        acceptance: AcceptanceRate? = nil, lastYear: Day? = nil
    ) {
        self.target = target
        self.name = name
        self.detail = detail
        self.category = category
        self.rank = rank
        self.coreRank = coreRank
        self.thcplRank = thcplRank
        self.place = place
        self.flags = flags
        self.meeting = meeting
        self.deadline = deadline
        self.abstractDeadline = abstractDeadline
        self.timeZone = timeZone
        self.state = state
        self.hasPassed = hasPassed
        self.isStarred = isStarred
        self.roundLabel = roundLabel
        self.note = note
        self.acceptance = acceptance
        self.lastYear = lastYear
    }

    /// `edition` as the list shows it: its next deadline, or a round still to be announced, or its
    /// last deadline once all have passed.
    init(series: ConferenceSeries, edition: ConferenceEdition, isStarred: Bool, now: Date) {
        let round = edition.round(id: nil, now: now)
        let deadline = round?.closingDate
        // A date is written but cannot be read: a time zone the app does not know, or a typo.
        let isUnreadable =
            !edition.rounds.contains { $0.closingDate != nil }
            && edition.rounds.contains { [$0.paper, $0.abstract].contains { $0?.isAnnounced == true } }
        let label = round?.label(roundCount: edition.rounds.count)
        self.init(
            target: Paper.Target(series: series.id, year: edition.year), name: series.title, detail: series.description,
            category: series.category, rank: series.displayRank, coreRank: series.displayCoreRank,
            thcplRank: series.displayThcplRank, place: edition.shortPlace, flags: edition.flags,
            meeting: edition.meeting,
            deadline: deadline, abstractDeadline: round?.paper?.date == nil ? nil : round?.abstract?.date,
            timeZone: edition.timeZone,
            state: deadline != nil ? .scheduled : isUnreadable ? .unreadable : .notAnnounced,
            hasPassed: deadline.map { $0 <= now } ?? false, isStarred: isStarred, roundLabel: label,
            note: round?.comment.flatMap { $0 == label ? nil : $0 }, acceptance: series.latestAcceptance,
            lastYear: edition.lastYear.flatMap { Day(string: String($0.paperDeadline.prefix(10))) })
    }

    /// "CVPR 2027".
    public var title: String {
        "\(name) \(String(target.year))"
    }

    public var id: String {
        Self.id(of: target)
    }

    /// The choice that stands for `target`: its edition, whichever round is fixed.
    public static func id(of target: Paper.Target) -> String {
        "\(target.series)|\(target.year)"
    }

    /// For sorting by deadline: what is ahead first, then what has passed or is not announced.
    public var deadlineOrder: Date { hasPassed ? .distantFuture : deadline ?? .distantFuture }
    /// For sorting by CCF rank: A, B and C, then the unranked.
    public var rankOrder: Int { ["A", "B", "C"].firstIndex(of: rank ?? "") ?? 9 }
    /// For sorting by acceptance rate, the hardest first and the unknown last.
    public var acceptanceOrder: Double { acceptance?.rate ?? 2 }
}

public enum TargetChoices {
    /// What the Conferences page lists, soonest deadline first.
    ///
    /// Without a search, the editions of the conferences that `filter` lets through whose
    /// deadline is still ahead or not announced yet, and those whose deadlines have passed when it
    /// includes them. A search looks through every conference and also finds past editions, for a
    /// paper that was submitted already. With `.following`, the
    /// starred conferences whatever their category and rank, by the last edition of one with nothing
    /// coming. The edition of `current`, a paper's target, is always there to be seen.
    public static func build(
        catalog: ConferenceCatalog, starred: Set<String>, filter: DeadlineFilter, current: Paper.Target?, now: Date
    ) -> [TargetChoice] {
        let isSearching = !filter.search.trimmingCharacters(in: .whitespaces).isEmpty
        let isStarredOnly = filter.scope == .following
        // A search looks past the categories and ranks, and so do the starred ones.
        let seriesFilter = isSearching || isStarredOnly ? DeadlineFilter(scope: .all, search: filter.search) : filter
        let currentYear = Calendar.gregorian(in: .gmt).component(.year, from: now)
        var choices: [TargetChoice] = []

        for series in catalog.series {
            let isStarred = starred.contains(series.id)
            let isListed = seriesFilter.matches(series) && (!isStarredOnly || isStarred)
            var listed: [TargetChoice] = []
            for edition in series.editions {
                let target = Paper.Target(series: series.id, year: edition.year)
                let isCurrent = current.map { TargetChoice.id(of: $0) == TargetChoice.id(of: target) } ?? false
                guard isListed || isCurrent else { continue }
                // Before the choice is made, as most editions are not listed: one with a deadline
                // ahead or a round still to be announced, one without dates while it is the coming
                // one, and one whose deadlines have all passed when those are asked for.
                let dates = edition.rounds.compactMap(\.closingDate)
                let isAhead = dates.contains { $0 > now } || edition.pendingRound(now: now) != nil
                let showsPassed = isSearching || filter.includesPassed
                guard isAhead || (dates.isEmpty ? edition.year >= currentYear : showsPassed) || isCurrent else {
                    continue
                }
                listed.append(TargetChoice(series: series, edition: edition, isStarred: isStarred, now: now))
            }
            if isStarredOnly, isListed, listed.isEmpty, let last = series.editions.last {
                listed.append(TargetChoice(series: series, edition: last, isStarred: true, now: now))
            }
            choices += listed
        }

        return choices.sorted {
            ($0.deadlineOrder, $0.title.lowercased()) < ($1.deadlineOrder, $1.title.lowercased())
        }
    }
}
