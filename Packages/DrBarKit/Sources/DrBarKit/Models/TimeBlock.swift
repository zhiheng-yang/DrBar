import Foundation

/// A stretch of days in a paper's plan, such as two weeks of writing.
public struct TimeBlock: Codable, Identifiable, Hashable, Sendable {
    /// What the block is for. The kind decides the name shown (translated) and the color.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case experiments, writing, review, buffer, custom
    }

    public var id: UUID
    public var kind: Kind
    /// The name of a `.custom` block. Ignored for the other kinds.
    public var customName: String
    public var start: Day
    /// The last day of the block (inclusive).
    public var end: Day
    public var isDone: Bool
    /// Who works on it besides the user, as `Person.id`s from the recipient groups. Empty for the
    /// user's own work.
    public var people: [UUID]

    public init(
        id: UUID = UUID(), kind: Kind, customName: String = "",
        start: Day, end: Day, isDone: Bool = false, people: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.customName = customName
        self.start = start
        self.end = end
        self.isDone = isDone
        self.people = people
    }

    /// The number of days, counting both the first and the last day.
    public var length: Int {
        start.days(to: end) + 1
    }

    public func contains(_ day: Day) -> Bool {
        start <= day && day <= end
    }

    /// Not done, and its last day is over.
    public func isOverdue(today: Day) -> Bool {
        !isDone && end < today
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, customName, start, end, isDone, people
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        let rawKind: String = c(.kind, default: Kind.custom.rawValue)
        let name: String = c(.customName, default: "")
        if let known = Kind(rawValue: rawKind) {
            kind = known
            customName = name
        } else {
            // A kind from a newer version becomes a custom block that keeps its name.
            kind = .custom
            customName = name.isEmpty ? rawKind : name
        }
        start = try c.required(.start)
        let lastDay: Day = try c.required(.end)
        // A hand-edited file may have the days the wrong way round.
        end = max(lastDay, start)
        isDone = c(.isDone, default: false)
        people = c(.people, default: [])
    }
}

extension TimeBlock {
    /// The part of a block held while dragging it on a timeline.
    public enum Handle: Sendable {
        /// The first day: dragging it changes when the block starts.
        case start
        /// The last day: dragging it changes when the block ends.
        case end
        /// The middle: dragging it moves the whole block.
        case body
    }

    /// The block after dragging `handle` by `days`. An end never passes the other one, so the
    /// block keeps at least one day.
    public func dragged(_ handle: Handle, by days: Int) -> TimeBlock {
        var block = self
        switch handle {
        case .start:
            block.start = min(start.adding(days), end)
        case .end:
            block.end = max(end.adding(days), start)
        case .body:
            block.start = start.adding(days)
            block.end = end.adding(days)
        }
        return block
    }

    /// Another round of the same work, with the same people, as long as this one, from the day after
    /// it ends.
    public func nextRound() -> TimeBlock {
        TimeBlock(kind: kind, customName: customName, start: end.adding(1), end: end.adding(length), people: people)
    }

    /// Where a block sits in a bar among the blocks on the same days: they share the bar's height,
    /// a track each, as events at the same time share a day's width in Calendar.
    public struct Track: Equatable, Sendable {
        public let index: Int
        public let count: Int

        public static let whole = Track(index: 0, count: 1)
    }

    /// The most blocks on any one day, which is how many tracks a bar needs for them.
    public static func trackCount(of blocks: [TimeBlock]) -> Int {
        tracks(of: blocks).values.map(\.count).max() ?? 1
    }

    /// Each block in the first track that is free on its days. Blocks that overlap, directly or
    /// through others, share as many tracks as the most of them on any one day; a block that
    /// overlaps nothing keeps the whole bar.
    public static func tracks(of blocks: [TimeBlock]) -> [TimeBlock.ID: Track] {
        var tracks: [TimeBlock.ID: Track] = [:]
        var group: [(id: TimeBlock.ID, index: Int)] = []
        // The last day of each track of the group so far.
        var trackEnds: [Day] = []
        func closeGroup() {
            for member in group {
                tracks[member.id] = Track(index: member.index, count: trackEnds.count)
            }
            group = []
            trackEnds = []
        }
        let ordered = blocks.enumerated().sorted {
            ($0.element.start, $0.element.end, $0.offset) < ($1.element.start, $1.element.end, $1.offset)
        }
        for block in ordered.map(\.element) {
            if let groupEnd = trackEnds.max(), groupEnd < block.start {
                closeGroup()
            }
            if let free = trackEnds.firstIndex(where: { $0 < block.start }) {
                trackEnds[free] = block.end
                group.append((block.id, free))
            } else {
                trackEnds.append(block.end)
                group.append((block.id, trackEnds.count - 1))
            }
        }
        closeGroup()
        return tracks
    }
}

/// One row of a paper's timeline: the blocks of one kind of work, in as many rounds as it takes,
/// such as all of the writing.
public struct BlockLane: Identifiable, Hashable, Sendable {
    public enum ID: Hashable, Sendable {
        case kind(TimeBlock.Kind)
        /// Custom blocks of one name.
        case custom(String)
    }

    public let id: ID
    public var blocks: [TimeBlock]

    /// The kinds of work every paper's plan has, in the order they come.
    public static let paperKinds: [TimeBlock.Kind] = [.experiments, .writing, .review, .buffer]
    /// The same for other work, which has no experiments.
    public static let workKinds: [TimeBlock.Kind] = [.writing, .review, .buffer]

    /// The lanes of `blocks`: the standard kinds in the order of the work, then any other kind and
    /// custom blocks by name, in the order they first appear. With `includingEmpty`, the standard
    /// kinds have a lane even without blocks, so that a first block can be drawn in it.
    public static func lanes(
        of blocks: [TimeBlock], includingEmpty: Bool = false, kinds: [TimeBlock.Kind] = paperKinds
    ) -> [BlockLane] {
        var lanes = kinds.map { BlockLane(id: .kind($0), blocks: []) }
        for block in blocks {
            let id = id(of: block)
            if let index = lanes.firstIndex(where: { $0.id == id }) {
                lanes[index].blocks.append(block)
            } else {
                lanes.append(BlockLane(id: id, blocks: [block]))
            }
        }
        return includingEmpty ? lanes : lanes.filter { !$0.blocks.isEmpty }
    }

    public static func id(of block: TimeBlock) -> ID {
        block.kind == .custom ? .custom(block.customName.trimmingCharacters(in: .whitespaces)) : .kind(block.kind)
    }

    /// A block of the lane's work from `start` to `end`.
    public func newBlock(from start: Day, to end: Day) -> TimeBlock {
        switch id {
        case let .kind(kind): TimeBlock(kind: kind, start: start, end: end)
        case let .custom(name): TimeBlock(kind: .custom, customName: name, start: start, end: end)
        }
    }

    /// Another round of the lane's work after its last one, or a first week of it; never before `today`.
    public func nextRound(today: Day) -> TimeBlock {
        guard let last = blocks.max(by: { $0.end < $1.end }) else {
            return newBlock(from: today, to: today.adding(6))
        }
        let round = last.nextRound()
        return round.start < today ? round.dragged(.body, by: round.start.days(to: today)) : round
    }
}

/// How a paper's plan is doing. Shown as an icon next to the paper's name.
public enum PlanStatus: Sendable {
    /// The paper has no time blocks.
    case noPlan
    case onTrack
    /// A block or a milestone that is not done is overdue.
    case behind
    /// A block runs past the deadline it works towards.
    case conflict
}
