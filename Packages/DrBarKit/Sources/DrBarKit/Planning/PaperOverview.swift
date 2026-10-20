import Foundation

/// Everything the lists show about one paper or item.
public struct PaperOverview: Hashable, Sendable {
    public var deadlines: PaperDeadlines
    public var status: PlanStatus
    public var progress: Double
    public var currentBlock: TimeBlock?

    public init(paper: Paper, catalog: ConferenceCatalog, now: Date, calendar: Calendar = .gregorianLocal) {
        let today = Day(now, calendar: calendar)
        deadlines = PaperDeadlines.resolve(paper, catalog: catalog, now: now, calendar: calendar)
        status = PlanMath.status(paper.blocks, milestones: paper.milestones, today: today, cutoffs: deadlines.cutoffs)
        progress = PlanMath.progress(paper.blocks)
        currentBlock = PlanMath.currentBlock(paper.blocks, today: today)
    }

    /// The deadline marked in red.
    public var flag: PaperDeadline? {
        deadlines.flag
    }

    public var cutoffs: Cutoffs {
        deadlines.cutoffs
    }

    /// The main deadline is there but has no date: not announced, or in a time zone the app cannot
    /// read.
    public var deadlineNotAnnounced: Bool {
        deadlines.main.map { $0.date == nil } ?? false
    }

    /// Where planning backwards counts from: the main deadline while it is open and has a date.
    public var planningDeadline: Date? {
        deadlines.main.flatMap { $0.isDone ? nil : $0.date }
    }
}
