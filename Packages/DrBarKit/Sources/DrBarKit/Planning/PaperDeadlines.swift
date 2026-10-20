import Foundation

/// One deadline of a paper or an item: a date its conference round lists, or one of its own.
public struct PaperDeadline: Hashable, Sendable, Identifiable {
    public enum Source: Hashable, Sendable {
        case conference(DeadlineKind)
        case own(UUID)
    }

    /// How it gets done.
    public enum Completion: Hashable, Sendable {
        /// Ticked off by itself: an own deadline, the abstract, the rebuttal, or anything of an item.
        case tick
        /// By marking the paper submitted: a paper's main deadline.
        case submission
        /// By the paper's decision, never by hand: the notification.
        case decision
    }

    /// The conference's `DeadlineItem.id`, such as `cvpr27|abstract|#1`, or an own deadline's id.
    public var id: String
    public var source: Source
    /// An own deadline's name as it was typed; empty for the conference's, named by their kind.
    public var title: String
    /// As ccfddl writes it, without a `date` while it is not announced or cannot be read; or an own
    /// deadline's date.
    public var value: DeadlineValue
    /// As it is written: the edition's time zone, or the one an own deadline was entered in.
    public var timeZone: String
    public var note: String
    public var isDone: Bool
    /// Done by the stage, or with a done item, so it cannot be ticked back on its own. A paper's
    /// main deadline is not, while marking the paper not submitted can take it back.
    public var isDoneByStage: Bool
    public var completion: Completion

    public init(
        id: String, source: Source, title: String = "", value: DeadlineValue, timeZone: String, note: String = "",
        isDone: Bool = false, isDoneByStage: Bool = false, completion: Completion = .tick
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.value = value
        self.timeZone = timeZone
        self.note = note
        self.isDone = isDone
        self.isDoneByStage = isDoneByStage
        self.completion = completion
    }

    public var date: Date? {
        value.date
    }

    /// The conference's kind of date; `nil` for an own deadline.
    public var kind: DeadlineKind? {
        if case let .conference(kind) = source { kind } else { nil }
    }

    public var ownID: UUID? {
        if case let .own(id) = source { id } else { nil }
    }

    /// The notification: nothing to do by it, it only comes.
    public var isEvent: Bool {
        kind == .decision
    }

    /// Done, or passed.
    public func isClosed(now: Date) -> Bool {
        isDone || (date.map { $0 <= now } ?? false)
    }
}

/// A paper's or an item's deadlines as they stand now: those of its conference's round and its own,
/// which one it aims at, which one is marked, and what its work is measured against.
public struct PaperDeadlines: Hashable, Sendable {
    /// The round of the conference a paper is submitted to.
    public struct Conference: Hashable, Sendable {
        /// "CVPR 2027".
        public var title: String
        /// "CVPR", the menu bar's name.
        public var seriesTitle: String
        public var roundLabel: String?
        public var timeZone: String
        public var source: DeadlineRow.Source

        public init(
            title: String, seriesTitle: String, roundLabel: String? = nil, timeZone: String, source: DeadlineRow.Source
        ) {
            self.title = title
            self.seriesTitle = seriesTitle
            self.roundLabel = roundLabel
            self.timeZone = timeZone
            self.source = source
        }

        /// "SIGMOD 2027 round 4", or "CVPR 2027" for an edition of one round.
        public var fullTitle: String {
            [title, roundLabel].compactMap { $0 }.joined(separator: " ")
        }
    }

    public var conference: Conference?
    /// By moment, those without one last; at the same moment, the conference's in the order of its
    /// cycle, then the own ones in the order they were added.
    public var all: [PaperDeadline]
    /// The one the plan aims at: the round's paper submission, or the own deadline chosen for it.
    public var main: PaperDeadline?
    /// The one marked in red: the main deadline until it is done, then the next one after it that
    /// is neither done nor passed.
    public var flag: PaperDeadline?
    public var cutoffs: Cutoffs
    /// Whether an own deadline can be made the main one: while there is no conference, and for a
    /// paper only before it is submitted.
    public var canChooseMain: Bool

    public init(
        conference: Conference? = nil, all: [PaperDeadline] = [], main: PaperDeadline? = nil,
        flag: PaperDeadline? = nil, cutoffs: Cutoffs = .none, canChooseMain: Bool = false
    ) {
        self.conference = conference
        self.all = all
        self.main = main
        self.flag = flag
        self.cutoffs = cutoffs
        self.canChooseMain = canChooseMain
    }

    public static func resolve(
        _ paper: Paper, catalog: ConferenceCatalog, now: Date, calendar: Calendar = .gregorianLocal
    ) -> PaperDeadlines {
        var list: [PaperDeadline] = []
        var conference: Conference?
        if let target = paper.target, let (series, edition) = catalog.edition(series: target.series, year: target.year),
            let round = edition.round(id: target.round, now: now)
        {
            conference = Conference(
                title: "\(series.title) \(String(edition.year))", seriesTitle: series.title,
                roundLabel: round.label(roundCount: edition.rounds.count), timeZone: edition.timeZone,
                source: .conference(series: series.id, edition: edition.id, round: round.id))
            for kind in DeadlineKind.allCases {
                guard let value = round.value(kind) else { continue }
                let id = DeadlineItem.id(edition: edition.id, kind: kind, round: round.id)
                let completion: PaperDeadline.Completion =
                    switch (paper.isPaper, kind) {
                    case (true, .paper): .submission
                    case (true, .decision): .decision
                    default: .tick
                    }
                list.append(
                    PaperDeadline(
                        id: id, source: .conference(kind), value: value, timeZone: edition.timeZone,
                        isDone: completion == .tick && paper.doneDeadlines.contains(id), completion: completion))
            }
        }
        // Without a conference; one that the catalog does not have yet is not stood in for.
        let ownMain = paper.target == nil ? paper.mainDeadline : nil
        for own in paper.deadlines {
            // A paper's main deadline is done by submitting it, whatever tick it had before.
            let completion: PaperDeadline.Completion = paper.isPaper && own.id == ownMain ? .submission : .tick
            list.append(
                PaperDeadline(
                    id: own.id.uuidString, source: .own(own.id), title: own.title,
                    value: DeadlineValue(raw: "", date: own.date), timeZone: own.timeZone, note: own.note,
                    isDone: completion == .tick && own.isDone, completion: completion))
        }
        list = list.enumerated().sorted { a, b in
            (a.element.date ?? .distantFuture, a.offset) < (b.element.date ?? .distantFuture, b.offset)
        }.map(\.element)

        let mainIndex =
            conference != nil
            ? list.firstIndex { $0.kind == .paper } : list.firstIndex { ownMain != nil && $0.ownID == ownMain }

        // What the stage has done: a submitted paper its abstract and its own deadlines before the
        // main one, and the main one, which marking it not submitted takes back; a decided one all
        // of those for good, and its conference's dates; a done item everything.
        let mainDate = mainIndex.flatMap { list[$0].date }
        for index in list.indices {
            let deadline = list[index]
            let isBeforeMain = mainDate.flatMap { main in deadline.date.map { $0 <= main } } ?? false
            let isDoneByStage =
                if !paper.isPaper {
                    paper.stage == .decided
                } else if paper.stage == .decided {
                    deadline.kind != nil || index == mainIndex || isBeforeMain
                } else if paper.stage.isSubmitted {
                    deadline.kind == .abstract || (deadline.kind == nil && isBeforeMain && index != mainIndex)
                } else {
                    false
                }
            if isDoneByStage || (paper.isPaper && paper.stage.isSubmitted && index == mainIndex) {
                list[index].isDone = true
                list[index].isDoneByStage = isDoneByStage
            }
        }

        var flag: Int?
        if let mainIndex {
            let main = list[mainIndex]
            if !main.isDone, main.date != nil {
                flag = mainIndex
            } else {
                flag = list.indices.first { index in
                    let deadline = list[index]
                    guard index != mainIndex, !deadline.isDone, let date = deadline.date, date > now else {
                        return false
                    }
                    // An undated main deadline still comes before what follows it in the cycle.
                    return main.date.map { date > $0 } ?? (deadline.kind == .rebuttal || deadline.kind == .decision)
                }
            }
        } else if paper.target == nil {
            // With none of its own aimed at, the next one is marked.
            flag = list.indices.first { !list[$0].isClosed(now: now) && list[$0].date != nil }
        }

        var cutoffs = Cutoffs.none
        if let mainIndex, let mainDate {
            let after = list.filter { deadline in
                !deadline.isDone && !deadline.isEvent && (deadline.date.map { $0 > mainDate } ?? false)
            }
            if !list[mainIndex].isDone {
                // The rebuttal only counts once the paper has gone in.
                let later = after.filter { $0.kind == nil }.compactMap(\.date)
                cutoffs = Cutoffs(days: ([mainDate] + later).map { Day($0, calendar: calendar) }, closesThePlan: true)
            } else {
                cutoffs = Cutoffs(
                    days: after.compactMap(\.date).map { Day($0, calendar: calendar) }, closesThePlan: false)
            }
        }

        return PaperDeadlines(
            conference: conference, all: list, main: mainIndex.map { list[$0] }, flag: flag.map { list[$0] },
            cutoffs: cutoffs, canChooseMain: paper.target == nil && !(paper.isPaper && paper.stage.isSubmitted))
    }

    /// The open deadlines ahead, soonest first.
    public func upcoming(after now: Date) -> [PaperDeadline] {
        all.filter { !$0.isDone && ($0.date.map { $0 > now } ?? false) }
    }

    /// The deadline ahead that comes next and is not done, which countdowns count to.
    public func next(after now: Date) -> PaperDeadline? {
        upcoming(after: now).first
    }

    /// Every date of its conference's round, done or not, which the paper speaks for over a star.
    public var coveredIDs: [String] {
        all.filter { $0.kind != nil }.map(\.id)
    }

    /// "CVPR 2027", or the name of the own deadline it aims at, when that has one.
    public var title: String? {
        conference?.title ?? main.flatMap { $0.title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.title }
    }

    /// The local days of its dated deadlines, which drags snap to.
    public func days(calendar: Calendar = .gregorianLocal) -> [Day] {
        all.compactMap { $0.date.map { Day($0, calendar: calendar) } }
    }
}

extension Paper {
    /// Whether work would run past a deadline of its own moved `days`.
    public func wouldRunPast(movingDeadline id: UUID, byDays days: Int, catalog: ConferenceCatalog, now: Date) -> Bool {
        var moved = self
        guard let index = moved.deadlines.firstIndex(where: { $0.id == id }) else { return false }
        moved.deadlines[index] = moved.deadlines[index].moved(byDays: days)
        let day = Day(moved.deadlines[index].date)
        let cutoffs = PaperDeadlines.resolve(moved, catalog: catalog, now: now).cutoffs
        return moved.blocks.contains { cutoffs.deadline(for: $0) == day && cutoffs.runsPast($0) }
    }
}
