import Foundation

/// Names beside marks on one line, as the deadlines of a paper's timeline have them. Each mark keeps
/// its place; its name goes after it, or before it where there is no room after, or shortened into
/// the room there is, or is left out, so that no two names, and no name and mark, ever touch. The
/// most important marks are named first, so the others only take what is left. A mark too close
/// to the end of the line turns to face back.
public enum LabelPlacement {
    public struct Mark: Equatable, Sendable {
        /// Where the mark stands.
        public var x: Double
        /// How wide its whole name is.
        public var width: Double
        /// Lower is named first.
        public var rank: Int
        /// The least room a shortened name is worth.
        public var minimum: Double
        /// Kept clear between its name and the other marks: less than between names for a name
        /// whose color already ties it to its own mark.
        public var clearance: Double

        public init(
            x: Double, width: Double, rank: Int, minimum: Double = 36, clearance: Double = LabelPlacement.clearance
        ) {
            self.x = x
            self.width = width
            self.rank = rank
            self.minimum = minimum
            self.clearance = clearance
        }
    }

    public struct Placement: Equatable, Sendable {
        public enum Side: Equatable, Sendable {
            case after, before
        }

        /// `nil` when there is no room for the name.
        public var side: Side?
        /// As wide as it is drawn: less than the whole name when shortened.
        public var width: Double
        /// The mark faces back, at the end of the line.
        public var isMirrored: Bool

        public init(side: Side?, width: Double, isMirrored: Bool = false) {
            self.side = side
            self.width = width
            self.isMirrored = isMirrored
        }
    }

    /// How wide a mark is, from its place to its far edge.
    public static let glyph = 9.0
    /// From a mark to its name.
    public static let gap = 2.0
    /// Kept clear between a name and any other name or mark.
    public static let clearance = 6.0
    /// Kept clear between a name and the other marks where its color already ties it to its own.
    public static let nearClearance = 3.0
    /// Kept clear of the ends of the line.
    public static let margin = 2.0

    /// The marks that stand as one, by index into `xs`: those that would be drawn over each other on
    /// a line `width` wide, in the order of their places.
    public static func clusters(_ xs: [Double], width: Double) -> [[Int]] {
        var clusters: [[Int]] = []
        for index in xs.indices.sorted(by: { xs[$0] < xs[$1] }) {
            if let last = clusters.last?.last,
                glyph(at: xs[index], width: width).lowerBound < glyph(at: xs[last], width: width).upperBound
            {
                clusters[clusters.count - 1].append(index)
            } else {
                clusters.append([index])
            }
        }
        return clusters
    }

    /// The marks to leave out so that the one ranked 0 is named in full, on a line that cannot be
    /// hovered for the names it leaves out: those in the way of its name after it, or before it
    /// where fewer are in the way there.
    public static func yielding(_ marks: [Mark], width: Double) -> Set<Int> {
        guard let first = marks.indices.filter({ marks[$0].rank == 0 }).min(by: { marks[$0].x < marks[$1].x })
        else { return [] }
        let mark = marks[first]
        let own = glyph(at: mark.x, width: width)
        let after = own.upperBound + gap...own.upperBound + gap + mark.width
        let before = own.lowerBound - gap - mark.width...own.lowerBound - gap
        let sides = (isMirrored(at: mark.x, width: width) ? [before] : [after, before]).filter {
            $0.lowerBound >= margin && $0.upperBound <= width - margin
        }
        let inTheWay = sides.map { side in
            let room = side.lowerBound - mark.clearance...side.upperBound + mark.clearance
            return Set(marks.indices.filter { $0 != first && glyph(at: marks[$0].x, width: width).overlaps(room) })
        }
        return inTheWay.min { $0.count < $1.count } ?? []
    }

    /// A mark too close to the end of the line faces back.
    static func isMirrored(at x: Double, width: Double) -> Bool {
        x + glyph > width - margin
    }

    /// Where a mark at `x` is drawn.
    static func glyph(at x: Double, width: Double) -> ClosedRange<Double> {
        isMirrored(at: x, width: width) ? x - glyph...x + 1 : x - 1...x + glyph
    }

    /// Where the names of `marks` go on a line `width` wide, in the order of `marks`.
    public static func place(_ marks: [Mark], width: Double) -> [Placement] {
        let mirrored = marks.map { isMirrored(at: $0.x, width: width) }
        let glyphs = marks.map { glyph(at: $0.x, width: width) }
        var taken: [ClosedRange<Double>] = []
        var placements = marks.indices.map { Placement(side: nil, width: 0, isMirrored: mirrored[$0]) }

        /// The room from `start` on, or up to it, before the end of the line or the next thing in
        /// the way.
        func room(from start: Double, forward: Bool, besides index: Int) -> Double {
            let names = taken.map { $0.lowerBound - clearance...$0.upperBound + clearance }
            let space = marks[index].clearance
            let others = glyphs.indices.filter { $0 != index }.map {
                glyphs[$0].lowerBound - space...glyphs[$0].upperBound + space
            }
            let around = names + others
            guard start >= margin, start <= width - margin, !around.contains(where: { $0.contains(start) }) else {
                return 0
            }
            if forward {
                return min(around.map(\.lowerBound).filter { $0 > start }.min() ?? width, width - margin) - start
            }
            return start - max(around.map(\.upperBound).filter { $0 < start }.max() ?? 0, margin)
        }

        for index in marks.indices.sorted(by: { (marks[$0].rank, marks[$0].x) < (marks[$1].rank, marks[$1].x) }) {
            let mark = marks[index]
            let afterStart = glyphs[index].upperBound + gap
            let beforeEnd = glyphs[index].lowerBound - gap
            let after = room(from: afterStart, forward: true, besides: index)
            let before = room(from: beforeEnd, forward: false, besides: index)
            // A mark that faces back is named before it.
            let sides: [(Placement.Side, Double)] =
                mirrored[index] ? [(.before, before)] : [(.after, after), (.before, before)]
            guard
                let (side, shown) = sides.first(where: { $0.1 >= mark.width }).map({ ($0.0, mark.width) })
                    ?? sides.max(by: { $0.1 < $1.1 }).flatMap({ $0.1 >= mark.minimum ? ($0.0, $0.1) : nil })
            else { continue }
            placements[index] = Placement(side: side, width: shown, isMirrored: mirrored[index])
            taken.append(side == .after ? afterStart...afterStart + shown : beforeEnd - shown...beforeEnd)
        }
        return placements
    }
}
