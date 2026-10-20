import DrBarKit
import SwiftUI

/// A paper's whole plan in one thin bar: a segment per block in the block's color, solid when done
/// and translucent when not, with today and the deadline marked. On the axis shared with the rows
/// around it, the bars of several papers can be compared.
public struct PlanProgressBar: View {
    public let blocks: [TimeBlock]
    public let deadline: Date?
    public let now: Date
    public var axis: TimeAxis
    public var height: CGFloat
    /// How far the marks stand out of the bar, above and below.
    public var overhang: CGFloat

    @Environment(\.barGrowth) private var growth

    public init(
        blocks: [TimeBlock], deadline: Date?, now: Date, axis: TimeAxis, height: CGFloat = 5, overhang: CGFloat = 2
    ) {
        self.blocks = blocks
        self.deadline = deadline
        self.now = now
        self.axis = axis
        self.height = height
        self.overhang = overhang
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (date: Date) in axis.x(date, width: width) }
            let marks = [
                deadline.flatMap { axis.contains($0) ? Mark(x: x($0), color: .red) : nil },
                axis.contains(now) ? Mark(x: x(now), color: .accentColor) : nil,
            ]
            .compactMap { $0 }
            let shown = blocks.filter { $0.end.endDate() > axis.start && $0.start.startDate() < axis.end }
            let tracks = TimeBlock.tracks(of: shown)
            let grown = Growth(today: x(now), share: growth)
            ZStack(alignment: .leading) {
                ForEach(shown) { block in
                    let x0 = grown(x(block.start.startDate()))
                    let x1 = grown(x(block.end.endDate()))
                    // Blocks on the same days sit one above the other, a point apart while there is
                    // room for that.
                    let track = tracks[block.id] ?? .whole
                    let gap: CGFloat = CGFloat(track.count) * 2 <= height ? 1 : 0
                    let trackHeight = max((height - CGFloat(track.count - 1) * gap) / CGFloat(track.count), 0.5)
                    RoundedRectangle.bar(height: trackHeight)
                        .fill(BlockColor.color(for: block).opacity(block.isDone ? 1 : Theme.undoneOpacity))
                        .frame(width: max(x1 - x0 - 1, 2), height: trackHeight)
                        .offset(x: x0, y: CGFloat(track.index) * (trackHeight + gap) - (height - trackHeight) / 2)
                }
                Marks(marks: marks, width: width)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: height + 2 * overhang)
        .accessibilityHidden(true)
    }
}

/// A thin tick through a small bar, such as today or a deadline.
private struct Mark {
    let x: CGFloat
    let color: Color
}

/// The ticks of a small bar, kept inside it, so that one at either end is drawn whole.
private struct Marks: View {
    let marks: [Mark]
    let width: CGFloat

    private static let markWidth: CGFloat = 1.5

    var body: some View {
        ForEach(marks.indices, id: \.self) { index in
            Capsule()
                .fill(marks[index].color)
                .frame(width: Self.markWidth)
                .offset(x: x(marks[index]))
        }
    }

    private func x(_ mark: Mark) -> CGFloat {
        min(max(mark.x, Self.markWidth / 2), width - Self.markWidth / 2) - Self.markWidth / 2
    }
}
