import Foundation

/// The days a paper's work is measured against: each block leads up to the first of them on or
/// after its start.
public struct Cutoffs: Hashable, Sendable {
    /// Ascending, each once.
    public var days: [Day]
    /// While the main deadline is still open, work after the last day runs past it too, as a plan
    /// dragged past the deadline does.
    public var closesThePlan: Bool

    public static let none = Cutoffs(days: [], closesThePlan: false)

    public init(days: [Day], closesThePlan: Bool) {
        self.days = Array(Set(days)).sorted()
        self.closesThePlan = closesThePlan
    }

    /// The deadline a block starting on `day` leads up to.
    public func deadline(for day: Day) -> Day? {
        days.first { $0 >= day } ?? (closesThePlan ? days.last : nil)
    }

    public func deadline(for block: TimeBlock) -> Day? {
        deadline(for: block.start)
    }

    public func runsPast(_ block: TimeBlock) -> Bool {
        deadline(for: block).map { block.end > $0 } ?? false
    }

    public func runsPast(_ day: Day) -> Bool {
        deadline(for: day).map { day > $0 } ?? false
    }
}

/// Progress, status and backward planning for a paper's time blocks.
public enum PlanMath {
    /// The share of the plan that is done, weighted by days: done days / all days.
    public static func progress(_ blocks: [TimeBlock]) -> Double {
        let total = blocks.reduce(0) { $0 + $1.length }
        guard total > 0 else { return 0 }
        let done = blocks.filter(\.isDone).reduce(0) { $0 + $1.length }
        return Double(done) / Double(total)
    }

    /// What shows of each of `spans` on one line where each is drawn over those before it: the
    /// parts of a span outside every span after it, in order.
    public static func visibleParts(_ spans: [Range<Double>]) -> [[Range<Double>]] {
        spans.indices.map { index in
            spans[(index + 1)...].reduce([spans[index]]) { parts, later in
                parts.flatMap { part -> [Range<Double>] in
                    guard part.overlaps(later) else { return [part] }
                    var rest: [Range<Double>] = []
                    if part.lowerBound < later.lowerBound { rest.append(part.lowerBound..<later.lowerBound) }
                    if later.upperBound < part.upperBound { rest.append(later.upperBound..<part.upperBound) }
                    return rest
                }
            }
        }
    }

    /// `.conflict` when a block runs past the deadline it leads up to; `.behind` when a block that
    /// is not done has already ended, or a milestone that is not done has passed.
    public static func status(
        _ blocks: [TimeBlock], milestones: [Milestone] = [], today: Day, cutoffs: Cutoffs
    ) -> PlanStatus {
        guard !blocks.isEmpty else { return .noPlan }
        if blocks.contains(where: cutoffs.runsPast) { return .conflict }
        if blocks.contains(where: { $0.isOverdue(today: today) })
            || milestones.contains(where: { $0.isOverdue(today: today) })
        {
            return .behind
        }
        return .onTrack
    }

    /// The milestone that comes next and is not done.
    public static func nextMilestone(_ milestones: [Milestone], today: Day) -> Milestone? {
        milestones.filter { !$0.isDone && $0.day >= today }.min { $0.day < $1.day }
    }

    /// The block to work on: the unfinished block that contains today, otherwise the next
    /// unfinished block to start. When blocks overlap, the one that started first wins.
    public static func currentBlock(_ blocks: [TimeBlock], today: Day) -> TimeBlock? {
        blocks.filter { !$0.isDone && $0.contains(today) }.min { $0.start < $1.start }
            ?? upcomingBlocks(blocks, today: today).first
    }

    /// Unfinished blocks that start after today, in order.
    public static func upcomingBlocks(_ blocks: [TimeBlock], today: Day) -> [TimeBlock] {
        blocks.filter { !$0.isDone && $0.start > today }.sorted { $0.start < $1.start }
    }

    /// The finished block that ended last.
    static func lastFinishedBlock(_ blocks: [TimeBlock]) -> TimeBlock? {
        blocks.filter(\.isDone).max { $0.end < $1.end }
    }

    /// The blocks in progress today that are not done.
    public static func blocksInProgress(_ blocks: [TimeBlock], today: Day) -> [TimeBlock] {
        blocks.filter { !$0.isDone && $0.contains(today) }.sorted { $0.start < $1.start }
    }

    /// Default blocks counted back from the deadline day: buffer 2 days, review 7 days,
    /// writing 14 days, and for a paper, everything from today until writing starts goes to
    /// experiments.
    ///
    /// Generated once, when the user asks; blocks are never moved automatically afterwards.
    /// When the first block starts before today, the plan does not fit (see `fits`).
    public static func backwardPlan(today: Day, deadline: Day, experiments: Bool = true) -> [TimeBlock] {
        let tail: [(TimeBlock.Kind, Int)] = [(.buffer, 2), (.review, 7), (.writing, 14)]
        var blocks: [TimeBlock] = []
        var cursor = deadline
        for (kind, length) in tail {
            let start = cursor.adding(-(length - 1))
            blocks.insert(TimeBlock(kind: kind, start: start, end: cursor), at: 0)
            cursor = start.adding(-1)
        }
        if experiments, cursor >= today {
            blocks.insert(TimeBlock(kind: .experiments, start: today, end: cursor), at: 0)
        }
        return blocks
    }

    /// Whether a plan starts no earlier than today.
    public static func fits(_ blocks: [TimeBlock], today: Day) -> Bool {
        guard let first = blocks.map(\.start).min() else { return true }
        return first >= today
    }
}
