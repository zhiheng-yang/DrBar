import DrBarKit
import SwiftUI

extension HoverCard {
    /// A time block, where it holds more than its bar shows: why it is marked, who works on it, or
    /// its name where the bar cuts it short or leaves it out, with its days. None for a block whose
    /// bar says it all.
    public static func block(
        _ block: TimeBlock, name: String, people: [Person], isNameShown: Bool, deadline: Day?, now: Date
    ) -> HoverCard? {
        let today = Day(now)
        var notes: [Line] = []
        if let deadline, block.end > deadline {
            notes.append(Line(CardText.endsAfterDeadline(deadline.days(to: block.end)), tone: .alert))
        }
        if block.isOverdue(today: today) {
            notes.append(Line(CardText.endedNotDone(today.days(to: block.end)), tone: .warning))
        }
        if !people.isEmpty {
            notes.append(Line(CardText.with(people)))
        }
        guard !notes.isEmpty || !isNameShown else { return nil }
        let days = Line("\(CardText.days(block.start, block.end)) · \(BlockText.days(block.length))", tone: .primary)
        return HoverCard(title: name, sections: [.lines([days] + notes)])
    }

    /// A milestone, where its diamond does not say what it is, or it is late: its day, and how far
    /// off it is.
    public static func milestone(_ milestone: Milestone, isNameShown: Bool, deadline: Day?, now: Date) -> HoverCard? {
        let today = Day(now)
        let isOverdue = milestone.isOverdue(today: today)
        let late = deadline.flatMap { !milestone.isDone && milestone.day > $0 ? $0.days(to: milestone.day) : nil }
        guard !isNameShown || isOverdue || late != nil else { return nil }
        let state =
            milestone.isDone
            ? CardText.done : isOverdue ? CardText.overdue : CardText.relative(today.days(to: milestone.day))
        var lines = [Line("\(CardText.date(milestone.day)) · \(state)", tone: isOverdue ? .warning : .primary)]
        if let late {
            lines.append(Line(CardText.afterDeadline(late), tone: .alert))
        }
        return HoverCard(title: milestone.displayName, sections: [.lines(lines)])
    }

    /// A paper or an item, over its name or, without blocks, its flag: what its row or line leaves
    /// out. Its conference where the row says something else or there is no row, what holds it up,
    /// who works on it, the moments of what is due next and the first of its open to-dos. None
    /// when there is nothing of the kind.
    public static func paper(
        _ paper: Paper, overview: PaperOverview, people: [UUID: Person], now: Date, hasRow: Bool = true
    ) -> HoverCard? {
        let today = Day(now)
        let subtitle = hasRow ? PaperText.subtitle(overview: overview) : nil
        var about: [Line] = []
        if let conference = overview.deadlines.conference, subtitle != conference.fullTitle {
            about.append(Line(conference.fullTitle))
        }
        if overview.deadlineNotAnnounced, subtitle != SharedText.deadlineNotAnnounced,
            overview.deadlines.next(after: now) == nil
        {
            about.append(Line(SharedText.deadlineNotAnnounced, tone: .tertiary))
        }
        if !hasRow, overview.deadlines.all.isEmpty {
            about.append(Line(CardText.noDeadline, tone: .tertiary))
        }
        if let problem = problem(of: paper, overview: overview, today: today) {
            about.append(problem)
        }
        var seen = Set<UUID>()
        let workers = paper.blocks.sorted { $0.start < $1.start }.flatMap(\.people)
            .filter { seen.insert($0).inserted }.compactMap { people[$0] }
        if !workers.isEmpty {
            about.append(Line(CardText.with(workers)))
        }
        let dates = overview.deadlines.upcoming(after: now).prefix(3).compactMap { deadline in
            deadline.date.map { dateLine(deadline.shortName, $0, now: now) }
        }
        let todos = paper.todos.filter { !$0.isDone && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        var list = todos.prefix(3).map { Line($0.title, symbol: "circle") }
        if todos.count > 3 {
            list.append(Line(CardText.more(todos.count - 3), tone: .tertiary))
        }
        let card = HoverCard(title: paper.displayTitle, sections: [.lines(about), .dates(Array(dates)), .lines(list)])
        return card.sections.isEmpty ? nil : card
    }

    /// The work that makes a plan behind, or the block that runs past its deadline.
    private static func problem(of paper: Paper, overview: PaperOverview, today: Day) -> Line? {
        switch overview.status {
        case .behind:
            if let late = paper.blocks.filter({ $0.isOverdue(today: today) }).min(by: { $0.end < $1.end }) {
                return Line(CardText.behind(late.displayName, due: late.end), tone: .warning)
            }
            if let late = paper.milestones.filter({ $0.isOverdue(today: today) }).min(by: { $0.day < $1.day }) {
                return Line(CardText.behind(late.displayName, due: late.day), tone: .warning)
            }
            return nil
        case .conflict:
            return paper.blocks.first(where: overview.cutoffs.runsPast).map {
                Line(CardText.conflict($0.displayName, end: $0.end), tone: .alert)
            }
        default:
            return nil
        }
    }

    /// One round of a conference: its full name, ranks and latest acceptance rate, and every date of
    /// the round with the time left; when its row is quiet, also what the row would say under its
    /// name.
    public static func conference(
        _ row: DeadlineRow, series: ConferenceSeries?, round: ConferenceRound?, edition: ConferenceEdition?,
        isQuiet: Bool, now: Date
    ) -> HoverCard {
        var about: [Line] = []
        if let series {
            if !series.description.isEmpty {
                about.append(Line(series.description))
            }
            let ranks = [
                series.displayRank.map(CCFCategory.rankName), series.displayCoreRank.map(CCFCategory.coreRankName),
                series.displayThcplRank.map(CCFCategory.thcplRankName),
            ]
            about.append(Line(([series.category] + ranks.compactMap { $0 }).joined(separator: " · ")))
            if let acceptance = series.latestAcceptance {
                about.append(Line(AcceptanceText.short(acceptance)))
            }
        }
        var dates: [DateLine] = []
        var notes: [Line] = []
        switch row.state {
        case .scheduled:
            for case let (kind, date?) in [(DeadlineKind.abstract, row.abstractDate), (.paper, row.paperDate)] {
                dates.append(dateLine(kind.shortName, date, now: now))
            }
            // What follows the submission, by the day.
            for case let (kind, date?) in [(DeadlineKind.rebuttal, row.rebuttalDate), (.decision, row.decisionDate)] {
                dates.append(
                    DateLine(name: kind.shortName, date: CardText.date(Day(date)), state: nil, isClosed: date <= now))
            }
        case .notAnnounced:
            if isQuiet {
                notes.append(Line(SharedText.notAnnounced))
            }
            if let previous = edition?.lastYear, let day = Day(string: String(previous.paperDeadline.prefix(10))) {
                notes.append(Line(CardText.lastYear(day), tone: .tertiary))
            }
        case .unreadable:
            notes.append(Line("\(row.rawDeadline ?? "") (\(row.timeZone))"))
            if isQuiet {
                notes.append(Line(DeadlineText.reason(row), tone: .warning))
            }
        }
        let place = edition?.place?.announcedText
        if isQuiet,
            let meeting = MeetingText.summary(
                place: place ?? row.place, flags: place == nil ? row.flags : nil, meeting: row.meeting)
        {
            notes.append(Line(meeting))
        }
        // A short comment is the round's label, which the title has.
        if let comment = round?.comment, comment != row.roundLabel {
            notes.append(Line(comment, tone: .tertiary))
        }
        return HoverCard(title: row.fullTitle, sections: [.lines(about), .dates(dates), .lines(notes)])
    }

    /// A deadline's flag, or several on nearly the same moment. One: its moment in local time with
    /// the time left, the time in its own time zone where that is another, and its conference or
    /// its note. Several: their moments lined up, under their conference.
    public static func deadlines(_ deadlines: [(deadline: PaperDeadline, context: String?)], now: Date) -> HoverCard? {
        guard let first = deadlines.first else { return nil }
        guard deadlines.count > 1 else {
            let deadline = first.deadline
            guard let date = deadline.date else { return nil }
            let line = dateLine(deadline.name, date, isDone: deadline.isDone, now: now)
            var lines = [
                Line(
                    [line.date, line.state].compactMap { $0 }.joined(separator: " · "),
                    tone: line.isClosed ? .secondary : .primary)
            ]
            if let own = DeadlineText.ownTime(date, deadline.timeZone) {
                lines.append(Line(own))
            }
            let note = deadline.note.split(separator: "\n").first.map(String.init)
            if let context = first.context ?? note {
                lines.append(Line(context, tone: .tertiary))
            }
            return HoverCard(title: deadline.name, sections: [.lines(lines)])
        }
        let contexts = Set(deadlines.map(\.context))
        let title =
            (contexts.count == 1 ? first.context : nil) ?? deadlines.map(\.deadline.name).joined(separator: " · ")
        let dates = deadlines.compactMap { deadline, _ in
            deadline.date.map { dateLine(deadline.shortName, $0, isDone: deadline.isDone, now: now) }
        }
        return HoverCard(title: title, sections: [.dates(dates)])
    }

    /// The flag of several pieces of work on a group's line, `titles`: when each deadline is due,
    /// by its name, or that it has no date yet.
    public static func dueWork(
        _ titles: [String], _ deadlines: [(name: String, deadline: PaperDeadline)], now: Date
    ) -> HoverCard? {
        let dates = deadlines.map { name, deadline in
            deadline.date.map { dateLine(name, $0, isDone: deadline.isDone, now: now) }
                ?? DateLine(
                    name: name, date: deadline.kind == nil ? CardText.noDeadline : SharedText.notAnnounced,
                    state: nil, isClosed: false)
        }
        guard !dates.isEmpty else { return nil }
        return HoverCard(title: titles.joined(separator: " · "), sections: [.dates(dates)])
    }

    /// "Paper   Fri, Nov 13, 7:59   30 days left"; done or passed, it steps back.
    private static func dateLine(_ name: String, _ date: Date, isDone: Bool = false, now: Date) -> DateLine {
        let state =
            isDone ? CardText.done : date <= now ? SharedText.passed : CountdownText.spoken(date.timeIntervalSince(now))
        return DateLine(
            name: name, date: DeadlineText.localDateTime(date), state: state, isClosed: isDone || date <= now)
    }
}

/// The words of hover cards.
enum CardText {
    /// "Sat, Oct 25 – Fri, Nov 7"
    static func days(_ start: Day, _ end: Day) -> String {
        guard end > start else { return date(start) }
        return "\(date(start)) – \(date(end))"
    }

    /// "Sat, Oct 25"
    static func date(_ day: Day) -> String {
        day.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "today", "tomorrow", "in 3 days", "2 days ago", as Calendar says it.
    static func relative(_ days: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: days))
    }

    static var done: String { String(localized: "Done", bundle: .module, comment: "Hover card: a block or milestone") }

    static var noDeadline: String {
        String(localized: "No deadline", bundle: .module, comment: "Hover card: work with no deadline yet")
    }

    static var overdue: String {
        String(localized: "Overdue", bundle: .module, comment: "Hover card: a milestone not done by its day")
    }

    static func endedNotDone(_ days: Int) -> String {
        String(
            localized: "Ended \(relative(days)), not done", bundle: .module,
            comment: "Hover card: e.g. Ended 2 days ago, not done")
    }

    static func with(_ people: [Person]) -> String {
        let names = people.map(\.displayName).formatted(.list(type: .and))
        return String(
            localized: "With \(names)", bundle: .module, comment: "Hover card: who works on a block or a paper")
    }

    /// A block that ends `days` after the deadline it leads up to.
    static func endsAfterDeadline(_ days: Int) -> String {
        String(
            localized: "Ends \(days) days after the deadline", bundle: .module,
            comment: "Hover card: a block past the deadline it leads up to")
    }

    /// A milestone `days` after the deadline it leads up to.
    static func afterDeadline(_ days: Int) -> String {
        String(
            localized: "\(days) days after the deadline", bundle: .module,
            comment: "Hover card: a milestone past the deadline it leads up to")
    }

    static func behind(_ name: String, due day: Day) -> String {
        String(
            localized: "Behind: \(name) was due \(date(day))", bundle: .module,
            comment: "Hover card: the work that makes a plan behind")
    }

    static func conflict(_ name: String, end: Day) -> String {
        String(
            localized: "Conflict: \(name) ends \(date(end)), after its deadline", bundle: .module,
            comment: "Hover card: the block that runs past the deadline it leads up to")
    }

    static func more(_ count: Int) -> String {
        String(localized: "and \(count) more", bundle: .module, comment: "Hover card: to-dos not listed")
    }

    static func lastYear(_ day: Day) -> String {
        let date = day.startDate().formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "Last year: \(date)", bundle: .module, comment: "Hover card: last year's deadline")
    }
}
