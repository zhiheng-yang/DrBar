import DrBarKit
import SwiftUI

/// A conference bar: a rounded rectangle from today to the submission deadline, so a shorter bar
/// means a closer deadline and the right ends show which comes first.
///
/// With an abstract registration deadline ahead, the bar is split in two: up to registration,
/// then, lighter, on to submission. A deadline that has passed shows as the faint end of a bar,
/// as long as the few days the axis shows before today. With `showsCycle`, what follows
/// (rebuttal, notification, the meeting itself) is marked faintly after the bar.
public struct DeadlineBar: View {
    public var axis: TimeAxis
    public let now: Date
    public let state: DeadlineRow.State
    /// `nil` when only the abstract deadline is known.
    public let paperDeadline: Date?
    public let abstractDeadline: Date?
    public var rebuttal: Date?
    public var decision: Date?
    public var meeting: MeetingDates?
    /// Marks rebuttal, notification and the meeting after the bar (details page).
    public var showsCycle: Bool
    /// A short "today" tick, for a bar shown on its own. Lists draw one line through all rows.
    public var showsTodayTick: Bool
    public var height: CGFloat

    @Environment(\.barGrowth) private var growth

    public init(
        axis: TimeAxis, now: Date, state: DeadlineRow.State = .scheduled, paperDeadline: Date?,
        abstractDeadline: Date?, rebuttal: Date? = nil, decision: Date? = nil, meeting: MeetingDates? = nil,
        showsCycle: Bool = false, showsTodayTick: Bool = true, height: CGFloat = Theme.deadlineBarHeight
    ) {
        self.axis = axis
        self.now = now
        self.state = state
        self.paperDeadline = paperDeadline
        self.abstractDeadline = abstractDeadline
        self.rebuttal = rebuttal
        self.decision = decision
        self.meeting = meeting
        self.showsCycle = showsCycle
        self.showsTodayTick = showsTodayTick
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x0 = axis.x(now, width: width)
            let grown = Growth(today: x0, share: growth)
            ZStack(alignment: .leading) {
                switch state {
                case .scheduled:
                    if let end = paperDeadline ?? abstractDeadline {
                        if showsCycle {
                            afterSubmission(end: end, width: width)
                        }
                        if let passed = lastPassed {
                            // The end of a bar, as long as the part of the axis before today.
                            let x = grown(
                                axis.x(max(axis.start, passed.addingTimeInterval(-axis.lookBack)), width: width))
                            RoundedRectangle.bar(height: height)
                                .fill(Palette.calm.opacity(Theme.pastOpacity))
                                .frame(width: max(grown(axis.x(passed, width: width)) - x, 4), height: height)
                                .offset(x: x)
                        }
                        if end > now, now < axis.end {
                            upcoming(to: end, from: x0, width: width, grown: grown)
                        }
                    }
                case .notAnnounced, .unreadable:
                    // A short dashed stub, so nothing suggests a date.
                    EmptyStub(height: height)
                        .offset(x: x0)
                }
                if showsTodayTick, axis.contains(now) {
                    TodayTick(height: height + 8)
                        .offset(x: x0 - TodayTick.width / 2)
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: height + 8)
        .accessibilityHidden(true)
    }

    /// The latest deadline of the row that has passed while still on the axis.
    private var lastPassed: Date? {
        [abstractDeadline, paperDeadline].compactMap { $0 }.filter { $0 <= now && $0 > axis.start }.max()
    }

    /// One bar to the deadline, or with a registration deadline ahead, one to registration and a
    /// lighter one on to submission. A bar that runs past the end of the axis gets a chevron. What
    /// is drawn is decided on the axis; while the bar grows, its ends are where `grown` puts them.
    @ViewBuilder
    private func upcoming(to end: Date, from x0: CGFloat, width: CGFloat, grown: Growth) -> some View {
        let x1 = axis.x(end, width: width)
        if let abstract = abstractDeadline, paperDeadline != nil, abstract > now, abstract < end {
            // Even a registration minutes away keeps its minimum length; submission starts after it.
            let xa = max(axis.x(abstract, width: width), x0 + Theme.minimumBarLength)
            let shownA = max(grown(xa), x0 + Theme.minimumBarLength)
            segment(until: abstract, from: x0, to: shownA)
            if x1 - xa > Theme.blockGap + 2 {
                let shown = max(grown(x1), shownA + Theme.blockGap)
                segment(until: end, from: shownA + Theme.blockGap, to: shown, opacity: 0.55)
                chevron(end: end, segmentStart: xa + Theme.blockGap, at: shown, width: width)
            } else {
                chevron(end: abstract, segmentStart: x0, at: shownA, width: width)
            }
        } else {
            let shown = max(grown(x1), x0 + Theme.minimumBarLength)
            segment(until: end, from: x0, to: shown)
            chevron(end: end, segmentStart: x0, at: shown, width: width)
        }
    }

    /// The part of the bar that leads to `deadline`, colored by how close it is.
    private func segment(until deadline: Date, from x0: CGFloat, to x1: CGFloat, opacity: Double = 1) -> some View {
        RoundedRectangle.bar(height: height)
            .fill(Urgency(secondsLeft: deadline.timeIntervalSince(now)).color.opacity(opacity))
            .frame(width: max(x1 - x0, 0), height: height)
            .offset(x: x0)
    }

    /// Beyond the range, the bar runs off the edge. Drawn at the bar's end, `x`, only where the
    /// last segment has room, and not on a thin bar, which says as much by running to the edge.
    @ViewBuilder
    private func chevron(end: Date, segmentStart: CGFloat, at x: CGFloat, width: CGFloat) -> some View {
        if end > axis.end, height >= 14, width - segmentStart >= height * 1.5 {
            Image(systemName: "chevron.right")
                .font(.system(size: height * 0.62, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
                .opacity(growth)
                .offset(x: x - height * 0.9)
        }
    }

    /// Rebuttal and notification as small rings and dots, the meeting as a short faint segment.
    @ViewBuilder
    private func afterSubmission(end: Date, width: CGFloat) -> some View {
        let mark = max(height * 0.5, 5)
        if let meeting {
            let start = meeting.start.startDate()
            let stop = meeting.end.endDate()
            if stop > max(end, axis.start), start < axis.end {
                let x = axis.x(max(start, end), width: width)
                let length = max(axis.x(stop, width: width) - x, mark)
                RoundedRectangle.bar(height: height * 0.45)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: length, height: height * 0.45)
                    .offset(x: x)
            }
        }
        if let rebuttal, rebuttal > end, axis.contains(rebuttal) {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: mark, height: mark)
                .offset(x: axis.x(rebuttal, width: width) - mark / 2)
        }
        if let decision, decision > end, axis.contains(decision) {
            Circle()
                .fill(Color.secondary)
                .frame(width: mark, height: mark)
                .offset(x: axis.x(decision, width: width) - mark / 2)
        }
    }
}

extension DeadlineBar: Animatable {
    /// Moves with the axis frame by frame, as the grid and the ticks do, so that what crosses an
    /// edge slides across it rather than fading in place.
    public nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }
}

/// A paper's plan: one segment per time block (solid = done, translucent = not done) and a tick at
/// each deadline, the flag's in red, with a little red flag standing on the bar beside it where the
/// row has room above it. Blocks done and over are faint; those over and not done stay
/// translucent, edged in orange. With `editing`, the blocks can be dragged to other days, and new
/// ones drawn across empty days; they move a whole day at a time, as the plan counts in days.
public struct PlanBar: View {
    public var axis: TimeAxis
    public let now: Date
    public let blocks: [TimeBlock]
    public var deadlines: [TimelineDeadline]
    /// Lines drawn over the bar by the timeline around it, which names keep clear of, as of ticks.
    public var lines: [Date]
    /// Diamonds on the bar's top edge, with a hover card each.
    public var milestones: [Milestone]
    public var height: CGFloat
    /// How tall the bar is where no blocks share days. Blocks keep the corners of a bar that high,
    /// however tall the bar has grown for its tracks.
    public var baseHeight: CGFloat?
    /// Writes block names inside segments wide enough for them (planner).
    public var showsNames: Bool
    /// Where the bar writes no names, whether its row writes the name of its blocks out whole.
    public var rowShowsWholeName: Bool
    /// A hover card per block where it holds more than it shows (planner).
    public var showsHelp: Bool
    /// The monograms of the people on a block, at its end, where there is room (planner).
    public var showsPeople: Bool
    public var blockName: (TimeBlock) -> String
    public var editing: BlockEditing?
    /// How much room the row leaves above the bar, where the red flag stands.
    public var flagRoom: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.planPeople) private var planPeople
    @Environment(\.axisLabels) private var axisLabels
    @Environment(\.barGrowth) private var growth
    /// A selection the keyboard does not act on is gray, as in Finder.
    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlActiveState) private var activeState
    @GestureState private var drag: BlockDrag?
    @GestureState private var drawing: BlockDrawing?
    /// The days of the last drag update, to feel each snap only once.
    @State private var lastDragDays: Int?
    @State private var lastDrawing: BlockDrawing?
    /// A block whose drag was cancelled with Esc; it stays put until the button comes up.
    @State private var cancelledDrag: TimeBlock.ID?
    @State private var isDrawingCancelled = false
    @State private var cancellation = DragCancellation()
    @State private var edgeScroll = EdgeScroll()
    /// The moment under the pointer, or the day, where the drag under way began.
    @State private var dragAnchor = DragAnchor<Date>()
    @State private var drawingStart = DragAnchor<Day>()
    /// Stands for a block while it is being drawn.
    @State private var drawingID = UUID()

    public init(
        axis: TimeAxis, now: Date, blocks: [TimeBlock], deadlines: [TimelineDeadline] = [], lines: [Date] = [],
        milestones: [Milestone] = [], height: CGFloat = Theme.planBarHeight, baseHeight: CGFloat? = nil,
        showsNames: Bool = false, rowShowsWholeName: Bool = true, showsHelp: Bool = false,
        showsPeople: Bool = false, blockName: @escaping (TimeBlock) -> String = { $0.displayName },
        editing: BlockEditing? = nil, flagRoom: CGFloat = 0
    ) {
        self.axis = axis
        self.now = now
        self.blocks = blocks
        self.deadlines = deadlines
        self.lines = lines
        self.milestones = milestones
        self.height = height
        self.baseHeight = baseHeight
        self.showsNames = showsNames
        self.rowShowsWholeName = rowShowsWholeName
        self.showsHelp = showsHelp
        self.showsPeople = showsPeople
        self.blockName = blockName
        self.editing = editing
        self.flagRoom = flagRoom
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                if let editing, editing.canDraw {
                    drawingSurface(editing: editing, width: width)
                }
                let shown = shownBlocks(width: width)
                let tracks = TimeBlock.tracks(of: shown)
                let marks =
                    DeadlineTicks.places(deadlines, axis: axis, width: width)
                    + lines.map {
                        axis.x($0, width: width)
                    }
                let grown = Growth(today: axis.x(now, width: width), share: growth)
                ForEach(shown) { block in
                    let end = block.end.endDate()
                    let start = axis.x(block.start.startDate(), width: width)
                    let stop = axis.x(end, width: width)
                    let isMoving = movingID == block.id
                    // A block dragged off the axis stays, so its drag can go on.
                    if stop > start || isMoving {
                        let x0 = grown(start)
                        let x1 = grown(stop)
                        let track = tracks[block.id] ?? .whole
                        let gap = Self.trackGap(height: height, tracks: track.count)
                        let trackHeight = max((height - CGFloat(track.count - 1) * gap) / CGFloat(track.count), 0.5)
                        let size = CGSize(width: max(x1 - x0 - Theme.blockGap, 3), height: trackHeight)
                        let label = BlockLabel(
                            name: showsNames ? blockName(block) : nil, people: showsPeople ? people(on: block) : [],
                            size: size, marks: isMoving ? [] : marks.map { $0 - x0 })
                        let segment = segment(
                            block, size: size, label: label, hasEnded: end <= now,
                            isSelected: editing?.selection == block.id && !isMoving)
                        Group {
                            if blocks.contains(where: { $0.id == block.id }) {
                                editable(segment, block: block, size: size, width: width)
                                    .hoverCard(id: block.id.uuidString) {
                                        guard showsHelp, !isEditing else { return nil }
                                        // Where the bar writes no names, its row does, as on a paper's page.
                                        return .block(
                                            block, name: blockName(block), people: people(on: block),
                                            isNameShown: showsNames ? label.showsWholeName : rowShowsWholeName,
                                            deadline: editing?.cutoffs.deadline(for: block), now: now)
                                    }
                            } else {
                                // A copy or a new block, which is not one of the blocks until it lands.
                                segment
                            }
                        }
                        .overlay(alignment: .top) {
                            if isMoving, let editing {
                                DragLabel(
                                    parts: [
                                        axisLabels.wrappedValue.showsDates ? BlockText.range(block) : nil,
                                        axisLabels.wrappedValue.showsDays
                                            ? RelativeDayText.range(block, today: Day(now)) : nil,
                                        BlockText.days(block.length),
                                    ]
                                    .compactMap { $0 },
                                    isPastDeadline: editing.cutoffs.runsPast(block)
                                )
                                .alignmentGuide(.top) { $0[.bottom] + 5 }
                            }
                        }
                        // Blocks on the same days sit one above the other.
                        .offset(x: x0, y: CGFloat(track.index) * (trackHeight + gap) - (height - trackHeight) / 2)
                        .zIndex(isMoving ? 1 : 0)
                    }
                }
                let diamond = min(height * 0.5, 9)
                DeadlineTicks(
                    deadlines: deadlines, diamonds: milestones.map { $0.date() }, axis: axis, now: now, height: height,
                    diamondSize: diamond, flagRoom: flagRoom
                )
                .frame(width: width, height: geo.size.height + 2 * flagRoom)
                if let flag = DeadlineTicks.flag(
                    deadlines, diamonds: milestones.map { $0.date() }, axis: axis, width: width, diamondSize: diamond,
                    room: flagRoom)
                {
                    // A card for the flag, as for those of a paper's page.
                    Color.clear
                        .frame(width: flag.rect.width + 4, height: flag.rect.height + 2)
                        .contentShape(Rectangle())
                        .hoverCard(id: "deadline|" + flag.deadline.id) {
                            .deadlines([(flag.deadline.deadline, flag.deadline.context)], now: now)
                        }
                        .offset(x: flag.rect.minX - 2, y: flag.rect.midY - height / 2)
                }
                let milestoneColors = BlockColor.colors(for: milestones, among: blocks)
                ForEach(milestones.filter { axis.contains($0.date()) }) { milestone in
                    let size = diamond
                    let color = milestoneColors[milestone.id] ?? Palette.calm
                    MilestoneDiamond(milestone, color: color, today: Day(now), size: size)
                        // Under the bar it sits on, rather than over it.
                        .hoverCard(id: milestone.id.uuidString, clearance: height) {
                            .milestone(
                                milestone, isNameShown: false,
                                deadline: editing?.cutoffs.deadline(for: milestone.day), now: now)
                        }
                        .offset(x: axis.x(milestone.date(), width: width) - size / 2, y: -height / 2)
                }
            }
            .coordinateSpace(.named(TrackSpace()))
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: height + 8)
        .accessibilityHidden(true)
    }

    /// How tall a bar of `blocks` is drawn: each of its tracks `trackHeight` high, as the user set
    /// it; or else `base`, or taller where blocks share days, so that each of them keeps a track of
    /// `Theme.trackHeight`.
    public static func height(for blocks: [TimeBlock], base: CGFloat, trackHeight: CGFloat? = nil) -> CGFloat {
        let tracks = CGFloat(TimeBlock.trackCount(of: blocks))
        let gaps = (tracks - 1) * Theme.blockGap
        guard let trackHeight else { return max(base, tracks * Theme.trackHeight + gaps) }
        return tracks * trackHeight + gaps
    }

    /// The space between the tracks of a bar `height` tall: as between blocks while each keeps
    /// 6 pt, a point while each keeps 2, then none, as a thin bar has so many blocks on one day.
    static func trackGap(height: CGFloat, tracks: Int) -> CGFloat {
        let count = CGFloat(tracks)
        if height >= count * 6 + (count - 1) * Theme.blockGap {
            return Theme.blockGap
        }
        return height >= count * 3 - 1 ? 1 : 0
    }

    /// How tall a row with a bar of `blocks` is: `rowHeight`, and as much more as the bar is
    /// taller than `base`.
    public static func rowHeight(
        for blocks: [TimeBlock], base: CGFloat, rowHeight: CGFloat, trackHeight: CGFloat? = nil
    ) -> CGFloat {
        rowHeight + height(for: blocks, base: base, trackHeight: trackHeight) - base
    }

    /// The drag under way, unless Esc has cancelled it.
    private var activeDrag: BlockDrag? {
        drag?.original.id == cancelledDrag ? nil : drag
    }

    private var activeDrawing: BlockDrawing? {
        isDrawingCancelled ? nil : drawing
    }

    private var isEditing: Bool {
        activeDrag != nil || activeDrawing != nil
    }

    /// The block that follows the pointer, with its days above it.
    private var movingID: TimeBlock.ID? {
        activeDrawing != nil ? drawingID : activeDrag.map { $0.copyID ?? $0.original.id }
    }

    /// The blocks as they are drawn: with the one being dragged where it is now, the copy being
    /// dragged, or the block being drawn.
    private func shownBlocks(width: CGFloat) -> [TimeBlock] {
        var shown = blocks
        if let drag = activeDrag {
            let moved = drag.block(on: axis, width: width)
            if drag.copyID == nil {
                shown = shown.map { $0.id == drag.original.id ? moved : $0 }
            } else {
                shown.append(moved)
            }
        }
        if let drawing = activeDrawing, let newBlock = editing?.newBlock {
            let days = drawing.days(on: axis, width: width)
            var block = newBlock(days.first, days.last)
            block.id = drawingID
            shown.append(block)
        }
        return shown
    }

    /// A block `size` big, with what `label` writes inside it.
    private func segment(
        _ block: TimeBlock, size: CGSize, label: BlockLabel, hasEnded: Bool, isSelected: Bool
    ) -> some View {
        let color = BlockColor.color(for: block)
        let corner = cornerRadius(size)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let isSolid = block.isDone && !hasEnded
        // Work that ended without being ticked off stays in view, edged in the color of "behind".
        let isOverdue = hasEnded && !block.isDone
        return
            shape
            .fill(color.opacity(isSolid ? 1 : block.isDone ? Theme.pastOpacity : Theme.undoneOpacity))
            .overlay {
                if isOverdue {
                    shape.strokeBorder(Color.orange, lineWidth: 1.5)
                } else if contrast == .increased, !isSolid {
                    shape.strokeBorder(color, lineWidth: 1)
                }
            }
            .overlay {
                HStack(spacing: 4) {
                    if let name = label.name {
                        Text(name)
                            .font(.system(size: label.nameSize, weight: .medium))
                            .foregroundStyle(isSolid ? Color.white : Color.primary.opacity(0.85))
                            .lineLimit(1)
                            .frame(maxWidth: label.nameWidth, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    if label.showsBadges {
                        PeopleBadges(label.people, color: color, size: label.badgeSize)
                    }
                }
                .padding(.horizontal, label.inset)
                // Inside the block while it grows.
                .clipped()
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                if isSelected {
                    // A ring around the block, its corners running alongside the block's.
                    RoundedRectangle(cornerRadius: corner + 3, style: .continuous)
                        .strokeBorder(
                            isFocused && activeState == .key ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary),
                            lineWidth: 2
                        )
                        .frame(width: size.width + 6, height: size.height + 6)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The corners of a block `size` big: those of every bar of its height, but no rounder than a
    /// bar of the base height, and no more than 40 % of its width, so that a block standing for
    /// several tracks never swells into a blob, nor a narrow one into a capsule.
    private func cornerRadius(_ size: CGSize) -> CGFloat {
        Theme.cornerRadius(height: min(size.height, size.width, baseHeight ?? height))
    }

    /// The people of the recipient groups that `block` names, as far as they are still there.
    private func people(on block: TimeBlock) -> [Person] {
        block.people.compactMap { planPeople[$0] }
    }

    // MARK: Editing

    @ViewBuilder
    private func editable(_ segment: some View, block: TimeBlock, size: CGSize, width: CGFloat) -> some View {
        if let editing {
            let base =
                segment
                .overlay {
                    handles(for: block, editing: editing, size: size, width: width)
                }
                .anchorPreference(key: TimelineBounds.self, value: .bounds) { [block.id: $0] }
            if editing.select != nil || editing.open != nil {
                base
                    // Every click selects the block at once; a double-click opens it as well.
                    .gesture(
                        TapGesture(count: 2).onEnded { editing.open?(block) }
                            .simultaneously(with: TapGesture().onEnded { editing.select?(block.id) })
                    )
                    .contextMenu { menu(for: block, editing: editing) }
            } else if editing.hasMenu {
                base.contextMenu { menu(for: block, editing: editing) }
            } else {
                base
            }
        } else {
            segment
        }
    }

    /// The ends are a few points wide; between them, the block moves as a whole. A short block
    /// gets a wider grip than it is long. An end cut off by the edge of the axis moves the block,
    /// as the real end is out of sight.
    private func handles(for block: TimeBlock, editing: BlockEditing, size: CGSize, width: CGFloat) -> some View {
        let gripWidth = max(size.width, 12)
        let edge = min(8, gripWidth / 3)
        // Decided by the block as it was, so a drag keeps its kind to the end.
        let original = blocks.first { $0.id == block.id } ?? block
        let startShows = original.start.startDate() >= axis.start
        let endShows = original.end.endDate() <= axis.end
        return HStack(spacing: 0) {
            handle(startShows ? .start : .body, of: block, editing: editing, width: width)
                .frame(width: edge)
            handle(.body, of: block, editing: editing, width: width)
            handle(endShows ? .end : .body, of: block, editing: editing, width: width)
                .frame(width: edge)
        }
        .frame(width: gripWidth, height: size.height)
    }

    private func handle(
        _ part: TimeBlock.Handle, of block: TimeBlock, editing: BlockEditing, width: CGFloat
    ) -> some View {
        // The moment under the pointer, in the bar area.
        func moment(_ location: CGPoint) -> Date {
            axis.date(atX: location.x, width: width)
        }
        func days(_ value: DragGesture.Value) -> Int {
            wholeDays(from: dragAnchor.value(for: value) ?? moment(value.startLocation), to: moment(value.location))
        }
        // Option held over the middle of a block drags a copy of it, as in Calendar and Finder.
        func copies() -> Bool {
            part == .body && editing.add != nil && NSEvent.modifierFlags.contains(.option)
        }
        return Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard drag == nil else { return }
                switch phase {
                case .active: BlockCursor.hover(part).set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(TrackSpace()))
                    .updating($drag) { value, state, _ in
                        guard let original = blocks.first(where: { $0.id == block.id }) else { return }
                        state = BlockDrag(
                            original: original, handle: part, anchor: state?.anchor ?? moment(value.startLocation),
                            x: value.location.x, copyID: copies() ? state?.copyID ?? UUID() : nil)
                    }
                    .onChanged { value in
                        if dragAnchor.value(for: value) == nil {
                            // A new drag, whatever became of the one before.
                            dragAnchor = DragAnchor(moment(value.startLocation), at: value.startLocation)
                            lastDragDays = nil
                            if cancelledDrag == block.id {
                                cancelledDrag = nil
                            }
                        }
                        guard cancelledDrag != block.id else { return }
                        cancellation.listen {
                            cancelledDrag = block.id
                            edgeScroll.stop()
                        }
                        BlockCursor.drag(part, copies: copies()).set()
                        edgeScroll.follow(x: value.location.x, width: width, pan: editing.pan)
                        let moved = days(value)
                        guard moved != lastDragDays else { return }
                        if lastDragDays != nil, let original = blocks.first(where: { $0.id == block.id }) {
                            feelSnap(original.dragged(part, by: moved), part, editing: editing)
                        }
                        lastDragDays = moved
                    }
                    .onEnded { value in
                        cancellation.stop()
                        edgeScroll.stop()
                        let moved = days(value)
                        dragAnchor = DragAnchor()
                        lastDragDays = nil
                        BlockCursor.hover(part).set()
                        guard cancelledDrag != block.id else {
                            cancelledDrag = nil
                            return
                        }
                        guard moved != 0, let original = blocks.first(where: { $0.id == block.id }) else { return }
                        if copies() {
                            var copy = original.dragged(.body, by: moved)
                            copy.id = UUID()
                            copy.isDone = false
                            editing.add?(copy)
                        } else {
                            editing.commit(original.dragged(part, by: moved), part)
                        }
                    })
    }

    /// Empty days under the blocks: drag across them to draw a block, double-click for a week from
    /// that day, click to clear the selection.
    private func drawingSurface(editing: BlockEditing, width: CGFloat) -> some View {
        func day(_ x: CGFloat) -> Day {
            Day(axis.date(atX: min(max(x, 0), width), width: width))
        }
        func drawn(_ value: DragGesture.Value) -> BlockDrawing {
            BlockDrawing(from: drawingStart.value(for: value) ?? day(value.startLocation.x), x: value.location.x)
        }
        return Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .updating($drawing) { value, state, _ in
                        state = BlockDrawing(from: state?.from ?? day(value.startLocation.x), x: value.location.x)
                    }
                    .onChanged { value in
                        if drawingStart.value(for: value) == nil {
                            // A new drawing, whatever became of the one before.
                            drawingStart = DragAnchor(day(value.startLocation.x), at: value.startLocation)
                            lastDrawing = nil
                            isDrawingCancelled = false
                        }
                        guard !isDrawingCancelled else { return }
                        cancellation.listen {
                            isDrawingCancelled = true
                            edgeScroll.stop()
                        }
                        edgeScroll.follow(x: value.location.x, width: width, pan: editing.pan)
                        let current = drawn(value)
                        guard current.to(on: axis, width: width) != lastDrawing?.to(on: axis, width: width) else {
                            return
                        }
                        if lastDrawing != nil {
                            feelSnap(current, width: width, editing: editing)
                        }
                        lastDrawing = current
                    }
                    .onEnded { value in
                        cancellation.stop()
                        edgeScroll.stop()
                        let days = drawn(value).days(on: axis, width: width)
                        drawingStart = DragAnchor()
                        lastDrawing = nil
                        guard !isDrawingCancelled else {
                            isDrawingCancelled = false
                            return
                        }
                        if let newBlock = editing.newBlock {
                            editing.add?(newBlock(days.first, days.last))
                        }
                    }
            )
            // The click that clears the selection comes first, so a double-click's new block stays selected.
            .gesture(
                TapGesture()
                    .onEnded { editing.select?(nil) }
                    .simultaneously(
                        with: SpatialTapGesture(count: 2).onEnded { value in
                            guard let newBlock = editing.newBlock else { return }
                            let first = day(value.location.x)
                            editing.add?(newBlock(first, first.adding(6)))
                        })
            )
    }

    /// A light tap of the trackpad when an end lands on today, the deadline or the edge of
    /// another block, as when an object snaps to a guide.
    private func feelSnap(_ block: TimeBlock, _ part: TimeBlock.Handle, editing: BlockEditing) {
        let guides = editing.guides(for: block, among: blocks, today: Day(now))
        let snaps =
            switch part {
            case .start: guides.starts.contains(block.start)
            case .end: guides.ends.contains(block.end)
            case .body: guides.starts.contains(block.start) || guides.ends.contains(block.end)
            }
        if snaps {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// The same while drawing, for the end that follows the pointer.
    private func feelSnap(_ drawing: BlockDrawing, width: CGFloat, editing: BlockEditing) {
        guard let newBlock = editing.newBlock else { return }
        let days = drawing.days(on: axis, width: width)
        let end: TimeBlock.Handle = drawing.to(on: axis, width: width) < drawing.from ? .start : .end
        feelSnap(newBlock(days.first, days.last), end, editing: editing)
    }

    @ViewBuilder
    private func menu(for block: TimeBlock, editing: BlockEditing) -> some View {
        let name = blockName(block)
        if let open = editing.open {
            Button {
                open(block)
            } label: {
                Text("Edit “\(name)”…", bundle: .module)
            }
        }
        if let add = editing.add {
            Button {
                add(block.nextRound())
            } label: {
                Text("Duplicate", bundle: .module)
            }
        }
        if let togglePerson = editing.togglePerson, !editing.people.isEmpty {
            Menu {
                ForEach(editing.people) { person in
                    Toggle(
                        person.displayName,
                        isOn: Binding(
                            get: { block.people.contains(person.id) }, set: { _ in togglePerson(block, person.id) }))
                }
            } label: {
                Text("With", bundle: .module, comment: "Menu of the people who work on a block")
            }
        }
        if let toggleDone = editing.toggleDone {
            Button {
                toggleDone(block)
            } label: {
                block.isDone ? Text("Mark as Not Done", bundle: .module) : Text("Mark as Done", bundle: .module)
            }
        }
        if let delete = editing.delete {
            Divider()
            Button(role: .destructive) {
                delete(block)
            } label: {
                Text("Delete “\(name)”", bundle: .module)
            }
        }
    }
}

extension PlanBar: Animatable {
    /// Moves with the axis frame by frame, as the grid and the ticks do, so that what crosses an
    /// edge slides across it rather than fading in place.
    public nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }
}

extension RoundedRectangle {
    /// The shape of every bar and block: the same rounded corners at every length.
    public static func bar(height: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cornerRadius(height: height), style: .continuous)
    }
}

/// A short dashed outline where a bar would be, for a date that is not known yet.
struct EmptyStub: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle.bar(height: height)
            .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: height * 3, height: height)
    }
}

/// The "today" mark on a bar shown on its own: a short accent tick that stands out of the bar.
struct TodayTick: View {
    let height: CGFloat

    static let width: CGFloat = 2.5

    var body: some View {
        Capsule()
            .fill(.tint)
            .frame(width: Self.width, height: height)
    }
}

/// What a block `size` big writes inside it: its name, smaller in a thinner track, and at its end
/// the monograms of its people while they fit, both clear of the ticks and lines at `marks`, which
/// are measured from the block's start.
@MainActor
private struct BlockLabel {
    let name: String?
    let nameSize: CGFloat
    /// The room the name has, which it is cut short to.
    let nameWidth: CGFloat
    let people: [Person]
    let badgeSize: CGFloat
    let showsBadges: Bool
    /// From the block's ends to what it writes.
    let inset: CGFloat

    init(name: String?, people: [Person], size: CGSize, marks: [CGFloat]) {
        let padding = min(7, size.height * 0.4)
        badgeSize = min(16, size.height - 9)
        // Monograms sit as far from the end as from the top and bottom.
        let badgeInset = max(3, (size.height - badgeSize) / 2)
        let badgesWidth = PeopleBadges.width(count: people.count, size: badgeSize)
        // The name stops short of the first tick inside the block, and the people show only where
        // there is room for them after the last one.
        let inside = marks.filter { $0 > 1 && $0 < size.width - 1 }
        let nameEnd = (inside.min() ?? size.width + 3) - 3
        let badgesStart = (inside.max().map { $0 + 3 }) ?? 0
        showsBadges =
            !people.isEmpty && badgeSize >= 13
            && size.width - max(badgesStart, padding) >= badgesWidth + badgeInset
        // Names get smaller with the bar, as in a track shared with other blocks, down to where
        // they would stop being readable.
        nameSize = min(10, size.height * 0.62)
        inset = showsBadges ? badgeInset : padding
        // From the inset as far as the monograms, or the end, let it, and short of the first tick.
        let nameRight = min(nameEnd, size.width - inset - (showsBadges ? badgesWidth + 8 : 4))
        nameWidth = max(nameRight - inset, 0)
        let room = min(nameEnd, size.width - (showsBadges ? badgesWidth + 4 : 0))
        self.name = nameSize >= 9 && room > nameSize * 5.2 && nameWidth > nameSize * 3 ? name : nil
        self.people = people
    }

    /// Whether the name is written out whole, neither cut short nor left out.
    var showsWholeName: Bool {
        name.map { CGFloat(TextWidth.of($0, size: nameSize, weight: .medium)) <= nameWidth } ?? false
    }
}
