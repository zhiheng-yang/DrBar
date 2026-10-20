import AppKit
import DrBarKit
import SwiftUI

/// What the milestone row of a paper's timeline lets the user do: drag a milestone to another day,
/// select it with a click, open it with a double click, tick it off or delete it, and add one
/// with a double click on an empty day.
public struct MilestoneEditing {
    /// What the paper's work is measured against: a milestone dragged past them is marked.
    public var cutoffs: Cutoffs
    /// The days of the paper's deadlines, which a dragged milestone can land on.
    public var deadlineDays: [Day]
    /// The paper's blocks, whose edges a dragged milestone can line up with.
    public var blocks: [TimeBlock]
    public var selection: UUID?
    public var commit: (Milestone) -> Void
    public var add: (Milestone) -> Void
    public var select: (UUID?) -> Void
    public var open: (Milestone) -> Void
    public var toggleDone: (Milestone) -> Void
    public var delete: (Milestone) -> Void
    /// Moves the axis by that many points while a drag is held at the edge of the row.
    public var pan: ((CGFloat) -> Void)?

    public init(
        cutoffs: Cutoffs, deadlineDays: [Day], blocks: [TimeBlock], selection: UUID?,
        commit: @escaping (Milestone) -> Void,
        add: @escaping (Milestone) -> Void, select: @escaping (UUID?) -> Void, open: @escaping (Milestone) -> Void,
        toggleDone: @escaping (Milestone) -> Void, delete: @escaping (Milestone) -> Void,
        pan: ((CGFloat) -> Void)? = nil
    ) {
        self.cutoffs = cutoffs
        self.deadlineDays = deadlineDays
        self.blocks = blocks
        self.selection = selection
        self.commit = commit
        self.add = add
        self.select = select
        self.open = open
        self.toggleDone = toggleDone
        self.delete = delete
        self.pan = pan
    }

    /// The days a dragged milestone is felt snapping onto: today, the deadlines, and the first and
    /// last days of the blocks.
    func guides(today: Day) -> Set<Day> {
        var days: Set<Day> = [today]
        days.formUnion(deadlineDays)
        for block in blocks {
            days.formUnion([block.start, block.end])
        }
        return days
    }
}

/// A milestone's diamond, in the color of the stage it falls in, as blocks are drawn: translucent
/// with a solid edge while it is ahead, solid once it is done, and edged in orange while it is
/// overdue, as late blocks are.
public struct MilestoneDiamond: View {
    public let milestone: Milestone
    public let color: Color
    public let today: Day
    public var size: CGFloat

    public init(_ milestone: Milestone, color: Color, today: Day, size: CGFloat) {
        self.milestone = milestone
        self.color = color
        self.today = today
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.15)
        shape
            .fill(color.opacity(milestone.isDone ? 1 : Theme.undoneOpacity))
            .overlay {
                shape.strokeBorder(milestone.isOverdue(today: today) ? Color.orange : color, lineWidth: 1.5)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(45))
            // What is done and over steps back, as finished blocks do.
            .opacity(milestone.isDone && milestone.day < today ? Theme.pastMilestoneOpacity : 1)
    }
}

/// A milestone while it is dragged: as it was, the moment that was under the pointer when the
/// drag began, and where the pointer is now in the row, as for blocks.
struct MilestoneDrag: Equatable {
    let original: Milestone
    let anchor: Date
    var x: CGFloat

    func milestone(on axis: TimeAxis, width: CGFloat) -> Milestone {
        original.moved(by: wholeDays(from: anchor, to: axis.date(atX: x, width: width)))
    }
}

/// The milestone row of a paper's timeline: each milestone as a diamond on its day with its name
/// beside it.
struct MilestoneTrack: View, Animatable {
    var axis: TimeAxis
    let now: Date
    let milestones: [Milestone]
    /// The paper's blocks, whose colors the milestones take.
    let blocks: [TimeBlock]
    let editing: MilestoneEditing?

    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.axisLabels) private var axisLabels
    @GestureState private var drag: MilestoneDrag?
    @State private var lastDays: Int?
    @State private var cancelledDrag: Milestone.ID?
    @State private var cancellation = DragCancellation()
    @State private var edgeScroll = EdgeScroll()
    @State private var dragAnchor = DragAnchor<Date>()

    static let size: CGFloat = 11

    /// Moves with the axis frame by frame, as the grid and the ticks do, so that what crosses an
    /// edge slides across it rather than fading in place.
    nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shown = shownMilestones(width: width).filter { axis.contains($0.date()) || $0.id == drag?.original.id }
            // Every diamond, so that a name stops before the next one.
            let marks = shown.map { axis.x($0.date(), width: width) }.sorted()
            let colors = BlockColor.colors(for: shown, among: blocks)
            ZStack(alignment: .leading) {
                if let editing {
                    surface(editing: editing, width: width)
                }
                ForEach(shown) { milestone in
                    let x = axis.x(milestone.date(), width: width)
                    let next = marks.first { $0 > x + 0.5 } ?? width + Self.size
                    // The name starts after the diamond's frame and ends a few points before the
                    // next diamond's tip, or at the end of the row.
                    mark(
                        milestone, color: colors[milestone.id] ?? Palette.calm, nameRoom: next - x - Self.size * 2 - 4,
                        width: width
                    )
                    .offset(x: x - Self.size)
                    .zIndex(drag?.original.id == milestone.id ? 1 : 0)
                }
            }
            .coordinateSpace(.named(TrackSpace()))
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    /// The milestones as they are drawn, with the one being dragged on its new day.
    private func shownMilestones(width: CGFloat) -> [Milestone] {
        guard let drag, drag.original.id != cancelledDrag else { return milestones }
        return milestones.map { $0.id == drag.original.id ? drag.milestone(on: axis, width: width) : $0 }
    }

    private func mark(_ milestone: Milestone, color: Color, nameRoom: CGFloat, width: CGFloat) -> some View {
        let isDragged = drag?.original.id == milestone.id && drag?.original.id != cancelledDrag
        let isSelected = editing?.selection == milestone.id && !isDragged
        let hasName = nameRoom >= 24
        return HStack(spacing: 4) {
            editable(
                MilestoneDiamond(milestone, color: color, today: Day(now), size: Self.size)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    isFocused && activeState == .key
                                        ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary),
                                    lineWidth: 2
                                )
                                .frame(width: Self.size + 7, height: Self.size + 7)
                                .rotationEffect(.degrees(45))
                        }
                    }
                    .frame(width: Self.size * 2, height: Self.size * 2.4)
                    .contentShape(Rectangle()),
                milestone: milestone, width: width
            )
            .hoverCard(id: milestone.id.uuidString) {
                isDragged
                    ? nil
                    : .milestone(
                        milestone, isNameShown: hasName && TextWidth.of(milestone.displayName) <= Double(nameRoom),
                        deadline: editing?.cutoffs.deadline(for: milestone.day), now: now)
            }
            .overlay(alignment: .top) {
                if isDragged, let editing {
                    DragLabel(
                        parts: [
                            axisLabels.wrappedValue.showsDates ? MilestoneText.day(milestone.day) : nil,
                            axisLabels.wrappedValue.showsDays
                                ? RelativeDayText.label(Day(now).days(to: milestone.day)) : nil,
                        ]
                        .compactMap { $0 },
                        isPastDeadline: editing.cutoffs.runsPast(milestone.day)
                    )
                    .alignmentGuide(.top) { $0[.bottom] + 2 }
                }
            }
            if hasName, !isDragged {
                Text(milestone.displayName)
                    .font(.caption)
                    .foregroundStyle(milestone.isDone ? .tertiary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: nameRoom, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Clicking and double-clicking a milestone, its menu, and, laid over it, the grip that drags it
    /// a day at a time, as a block's are.
    @ViewBuilder
    private func editable(_ diamond: some View, milestone: Milestone, width: CGFloat) -> some View {
        if let editing {
            diamond
                .overlay { grip(milestone, editing: editing, width: width) }
                .gesture(
                    TapGesture(count: 2).onEnded { editing.open(milestone) }
                        .simultaneously(with: TapGesture().onEnded { editing.select(milestone.id) })
                )
                .contextMenu {
                    Button {
                        editing.open(milestone)
                    } label: {
                        Text("Edit “\(milestone.displayName)”…", bundle: .module)
                    }
                    Button {
                        editing.toggleDone(milestone)
                    } label: {
                        milestone.isDone
                            ? Text("Mark as Not Done", bundle: .module) : Text("Mark as Done", bundle: .module)
                    }
                    Divider()
                    Button(role: .destructive) {
                        editing.delete(milestone)
                    } label: {
                        Text("Delete “\(milestone.displayName)”", bundle: .module)
                    }
                }
                .anchorPreference(key: TimelineBounds.self, value: .bounds) { [milestone.id: $0] }
        } else {
            diamond
        }
    }

    private func grip(_ shown: Milestone, editing: MilestoneEditing, width: CGFloat) -> some View {
        // Measured from the milestone as it was, not as it is drawn while it moves.
        let milestone = milestones.first { $0.id == shown.id } ?? shown
        return Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard drag == nil else { return }
                switch phase {
                case .active: NSCursor.openHand.set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(TrackSpace()))
                    .updating($drag) { value, state, _ in
                        state = MilestoneDrag(
                            original: milestone, anchor: state?.anchor ?? moment(value.startLocation, width),
                            x: value.location.x)
                    }
                    .onChanged { value in
                        if dragAnchor.value(for: value) == nil {
                            // A new drag, whatever became of the one before.
                            dragAnchor = DragAnchor(moment(value.startLocation, width), at: value.startLocation)
                            lastDays = nil
                            if cancelledDrag == milestone.id {
                                cancelledDrag = nil
                            }
                        }
                        guard cancelledDrag != milestone.id else { return }
                        cancellation.listen {
                            cancelledDrag = milestone.id
                            edgeScroll.stop()
                        }
                        NSCursor.closedHand.set()
                        edgeScroll.follow(x: value.location.x, width: width, pan: editing.pan)
                        let moved = days(value, width)
                        guard moved != lastDays else { return }
                        if lastDays != nil, editing.guides(today: Day(now)).contains(milestone.day.adding(moved)) {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        lastDays = moved
                    }
                    .onEnded { value in
                        cancellation.stop()
                        edgeScroll.stop()
                        let moved = days(value, width)
                        dragAnchor = DragAnchor()
                        lastDays = nil
                        NSCursor.openHand.set()
                        guard cancelledDrag != milestone.id else {
                            cancelledDrag = nil
                            return
                        }
                        if moved != 0 {
                            editing.commit(milestone.moved(by: moved))
                        }
                    }
            )
    }

    /// The moment under the pointer at `location`, in the row.
    private func moment(_ location: CGPoint, _ width: CGFloat) -> Date {
        axis.date(atX: location.x, width: width)
    }

    private func days(_ value: DragGesture.Value, _ width: CGFloat) -> Int {
        wholeDays(
            from: dragAnchor.value(for: value) ?? moment(value.startLocation, width), to: moment(value.location, width))
    }

    /// Empty days: a double click adds a milestone there, a click clears the selection.
    private func surface(editing: MilestoneEditing, width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                TapGesture()
                    .onEnded { editing.select(nil) }
                    .simultaneously(
                        with: SpatialTapGesture(count: 2).onEnded { value in
                            let x = min(max(value.location.x, 0), width)
                            editing.add(Milestone(day: Day(axis.date(atX: x, width: width))))
                        })
            )
    }
}
