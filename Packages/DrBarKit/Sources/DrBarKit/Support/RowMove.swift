import Foundation

/// One of a column of rows, dragged to another place: where it lands, and how far the rows it
/// passes step aside to make room. It lands past a row once its leading edge is past the middle of
/// that row, so rows of different heights take turns as the eye expects.
public struct RowMove: Equatable, Sendable {
    /// The index of the dragged row.
    public var from: Int
    /// How far it has been dragged down, in points; negative when up.
    public var translation: Double

    public init(from: Int, translation: Double) {
        self.from = from
        self.translation = translation
    }

    /// Where the row lands among rows of `heights`.
    public func destination(heights: [Double]) -> Int {
        guard heights.indices.contains(from) else { return 0 }
        let tops = heights.reduce(into: [0.0]) { $0.append($0[$0.count - 1] + $1) }
        let top = tops[from] + translation
        var to = from
        if translation > 0 {
            let bottom = top + heights[from]
            while to + 1 < heights.count, bottom > tops[to + 1] + heights[to + 1] / 2 {
                to += 1
            }
        } else {
            while to > 0, top < tops[to - 1] + heights[to - 1] / 2 {
                to -= 1
            }
        }
        return to
    }

    /// How far the row at `index` is drawn from its place: the dragged one follows the pointer,
    /// and each one it passes steps aside by the dragged row's height.
    public func offset(ofRowAt index: Int, heights: [Double]) -> Double {
        if index == from { return translation }
        guard heights.indices.contains(from) else { return 0 }
        let to = destination(heights: heights)
        if from < to, index > from, index <= to { return -heights[from] }
        if to < from, index >= to, index < from { return heights[from] }
        return 0
    }

    /// How far the dragged row's top is from its old place once it has landed, to settle it there.
    public func landing(heights: [Double]) -> Double {
        let to = destination(heights: heights)
        if to > from { return heights[(from + 1)...to].reduce(0, +) }
        if to < from { return -heights[to..<from].reduce(0, +) }
        return 0
    }

    /// `ids` with the dragged one moved to where it lands.
    public func apply<ID>(to ids: [ID], heights: [Double]) -> [ID] {
        guard ids.indices.contains(from) else { return ids }
        var result = ids
        let id = result.remove(at: from)
        result.insert(id, at: destination(heights: heights))
        return result
    }

    /// The same for `count` rows of one height.
    public func destination(rowHeight: Double, count: Int) -> Int {
        destination(heights: Array(repeating: rowHeight, count: count))
    }

    public func offset(ofRowAt index: Int, rowHeight: Double, count: Int) -> Double {
        offset(ofRowAt: index, heights: Array(repeating: rowHeight, count: count))
    }

    public func apply<ID>(to ids: [ID], rowHeight: Double) -> [ID] {
        apply(to: ids, heights: Array(repeating: rowHeight, count: ids.count))
    }

    /// The order of `all` once the rows that were shown, some of them, are in `shownOrder`; the
    /// rows that were not shown keep their places.
    public static func merge<ID: Hashable>(_ shownOrder: [ID], into all: [ID]) -> [ID] {
        let shown = Set(shownOrder)
        var next = shownOrder.makeIterator()
        return all.map { shown.contains($0) ? next.next() ?? $0 : $0 }
    }
}
