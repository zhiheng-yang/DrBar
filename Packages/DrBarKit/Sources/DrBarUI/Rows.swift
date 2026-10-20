import DrBarKit
import SwiftUI

/// A deadline row, like a line of a Gantt chart: the conference in the name column, with where
/// and when it meets under it where the row is tall enough, and its bar beside them on the shared
/// axis. A quiet row, under the papers and groups, has only the name and a thin bar.
public struct DeadlineRowView: View {
    public let row: DeadlineRow
    public let axis: TimeAxis
    public let now: Date
    public var labelWidth: CGFloat
    public var metrics: RowMetrics
    public var isQuiet: Bool
    /// What the row's hover card says about the conference.
    public var card: HoverCardSource?

    public init(
        row: DeadlineRow, axis: TimeAxis, now: Date, labelWidth: CGFloat = Theme.labelWidth,
        metrics: RowMetrics = AppSettings.RowSize.large.menuBarWindow, isQuiet: Bool = false,
        card: HoverCardSource? = nil
    ) {
        self.row = row
        self.axis = axis
        self.now = now
        self.labelWidth = labelWidth
        self.metrics = metrics
        self.isQuiet = isQuiet
        self.card = card
    }

    public var body: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                if isQuiet {
                    title
                        .font(.callout)
                } else {
                    RowLabel(subtitle: metrics.showsSubtitle ? subtitle : nil) {
                        title
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isQuiet ? (hasPassed ? .tertiary : .secondary) : (hasPassed ? .secondary : .primary))
            .frame(width: labelWidth, alignment: .leading)
            DeadlineBar(
                axis: axis, now: now, state: row.state, paperDeadline: row.paperDate,
                abstractDeadline: row.abstractDate, showsTodayTick: false, height: metrics.barHeight
            )
            .frame(maxHeight: .infinity)
            .background(AxisGrid(axis: axis, now: now))
        }
        .frame(height: metrics.rowHeight)
        .contentShape(Rectangle())
        .hoverCard(card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DeadlineText.spoken(row, now: now))
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(row.name)
                .fontWeight(isQuiet ? .regular : .medium)
                .lineLimit(1)
                .truncationMode(.tail)
            if let year = row.year {
                Text(String(year))
                    .foregroundStyle(isQuiet ? .tertiary : .secondary)
                    .fixedSize()
            }
            if let round = row.roundLabel {
                Text(round)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Where and when the conference takes place, or why there is no bar.
    private var subtitle: String? {
        switch row.state {
        case .scheduled: MeetingText.summary(place: row.place, flags: row.flags, meeting: row.meeting)
        case .notAnnounced: SharedText.notAnnounced
        case .unreadable: DeadlineText.reason(row)
        }
    }

    private var hasPassed: Bool {
        row.state == .scheduled && (row.endDate.map { $0 <= now } ?? false)
    }
}

extension RowMetrics {
    /// How tall a paper's row of `blocks` is at rest: taller where blocks share days, in rows that
    /// grow.
    @MainActor
    public func paperRowHeight(for blocks: [TimeBlock], trackHeight: CGFloat? = nil) -> CGFloat {
        guard grows else { return rowHeight }
        return PlanBar.rowHeight(for: blocks, base: barHeight, rowHeight: rowHeight, trackHeight: trackHeight)
    }
}

/// A paper row: its title and target in the name column, its plan beside them on the shared axis.
/// A large bar grows where blocks share days; with `resize`, the row's lower edge can be dragged to
/// make its tracks taller or shorter. Dragged back to where the bar fits the blocks, or double
/// clicked, it fits them again. A smaller row keeps its height, sharing it among blocks on the same
/// days, and has no line under its name.
public struct PaperRowView<Accessory: View>: View {
    public let title: String
    public let blocks: [TimeBlock]
    public var milestones: [Milestone]
    public let overview: PaperOverview
    public let axis: TimeAxis
    public let now: Date
    public var labelWidth: CGFloat
    public var metrics: RowMetrics
    /// Block names and people inside the bars where they fit, and a card per block where it holds
    /// more than it shows.
    public var isDetailed: Bool
    public var editing: BlockEditing?
    public var labelDrag: LabelDrag?
    /// How tall each track of the bar is, as the user set it, in place of what fits the blocks.
    public var trackHeight: CGFloat?
    /// Called with the new height of each track when the row's edge has been dragged, or `nil` when
    /// the bar fits the blocks again.
    public var resize: ((CGFloat?) -> Void)?
    /// What the hover card of the name column says about the paper.
    public var card: HoverCardSource?
    private let accessory: Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the row's edge has been dragged.
    @GestureState private var resizing: CGFloat = 0
    /// Whether the dragged edge is where the bar fits the blocks, while it is dragged.
    @State private var resizeFits: Bool?
    @State private var isResizeCancelled = false
    @State private var cancellation = DragCancellation()

    public init(
        title: String, blocks: [TimeBlock], milestones: [Milestone] = [], overview: PaperOverview, axis: TimeAxis,
        now: Date, labelWidth: CGFloat = Theme.labelWidth,
        metrics: RowMetrics = AppSettings.RowSize.large.menuBarWindow, isDetailed: Bool = false,
        editing: BlockEditing? = nil, labelDrag: LabelDrag? = nil, trackHeight: CGFloat? = nil,
        resize: ((CGFloat?) -> Void)? = nil, card: HoverCardSource? = nil, @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.blocks = blocks
        self.milestones = milestones
        self.overview = overview
        self.axis = axis
        self.now = now
        self.labelWidth = labelWidth
        self.metrics = metrics
        self.isDetailed = isDetailed
        self.editing = editing
        self.labelDrag = labelDrag
        self.trackHeight = trackHeight
        self.resize = resize
        self.card = card
        self.accessory = accessory()
    }

    private var barHeight: CGFloat {
        metrics.barHeight
    }

    private var shownBarHeight: CGFloat {
        guard metrics.grows else { return barHeight }
        guard resizing != 0, !isResizeCancelled else {
            return PlanBar.height(for: blocks, base: barHeight, trackHeight: trackHeight)
        }
        return resized(by: resizing).height
    }

    /// The bar with its edge dragged `translation` points: each track a whole number of points
    /// high, from 16 to 64, and the height that fits the blocks when it comes within 3 points of it.
    private func resized(by translation: CGFloat) -> (height: CGFloat, trackHeight: CGFloat?) {
        let tracks = CGFloat(TimeBlock.trackCount(of: blocks))
        let gaps = (tracks - 1) * Theme.blockGap
        let start = PlanBar.height(for: blocks, base: barHeight, trackHeight: trackHeight)
        let track = min(max(((start + translation - gaps) / tracks).rounded(), 16), 64)
        let fitting = PlanBar.height(for: blocks, base: barHeight)
        let height = PlanBar.height(for: blocks, base: barHeight, trackHeight: track)
        return abs(height - fitting) <= 3 ? (fitting, nil) : (height, track)
    }

    public var body: some View {
        let bar = shownBarHeight
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                RowLabel(subtitle: subtitle) {
                    name
                }
                Spacer(minLength: 0)
                accessory
            }
            .frame(width: labelWidth, alignment: .leading)
            .contentShape(Rectangle())
            .hoverCard(card)
            .gesture(labelDrag.map(\.gesture))
            PlanBar(
                axis: axis, now: now, blocks: blocks, deadlines: overview.deadlines.timeline(now: now),
                milestones: milestones, height: bar, baseHeight: barHeight, showsNames: isDetailed,
                showsHelp: isDetailed, showsPeople: isDetailed, editing: editing,
                flagRoom: (metrics.rowHeight - barHeight) / 2
            )
            .frame(maxHeight: .infinity)
            .background(AxisGrid(axis: axis, now: now))
            .overlay(alignment: .bottom) { resizeEdge }
        }
        .frame(height: metrics.rowHeight + bar - barHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PaperText.spoken(title: title, overview: overview, now: now))
    }

    /// The lower edge of the bar area, which can be dragged up and down. It snaps, with a tap of the
    /// trackpad, to where the bar fits the blocks; Esc puts it back.
    @ViewBuilder
    private var resizeEdge: some View {
        if let resize, metrics.grows {
            Color.clear
                .frame(height: 7)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active: Self.resizeCursor.set()
                    case .ended: if resizeFits == nil { NSCursor.arrow.set() }
                    }
                }
                .gesture(
                    // In the window's coordinates: the edge itself moves with the drag.
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .updating($resizing) { value, state, _ in state = value.translation.height }
                        .onChanged { value in
                            Self.resizeCursor.set()
                            cancellation.listen { isResizeCancelled = true }
                            let fits = resized(by: value.translation.height).trackHeight == nil
                            if fits, resizeFits == false, !isResizeCancelled {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                            resizeFits = fits
                        }
                        .onEnded { value in
                            cancellation.stop()
                            resizeFits = nil
                            NSCursor.arrow.set()
                            guard !isResizeCancelled else {
                                isResizeCancelled = false
                                return
                            }
                            let height = resized(by: value.translation.height).trackHeight
                            if height != trackHeight {
                                resize(height)
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    guard trackHeight != nil else { return }
                    withAnimation(reduceMotion ? nil : .settle) { resize(nil) }
                }
        }
    }

    private static var resizeCursor: NSCursor {
        if #available(macOS 15, *) {
            return .frameResize(position: .bottom, directions: .all)
        }
        return .resizeUpDown
    }

    private var subtitle: String? {
        metrics.showsSubtitle ? PaperText.subtitle(overview: overview) : nil
    }

    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(title.isEmpty ? String(localized: "Untitled paper", bundle: .module) : title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            if let symbol = overview.status.symbolName {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(overview.status.color)
                    .symbolRenderingMode(.hierarchical)
                    .help(card == nil ? overview.status.localizedDescription : "")
            }
        }
    }

}

/// What dragging a row by its name does, such as reordering the rows: called with how far the
/// pointer has moved down, and once more when it is let go.
@MainActor
public struct LabelDrag {
    public var changed: (CGFloat) -> Void
    public var ended: (CGFloat) -> Void

    public init(changed: @escaping (CGFloat) -> Void, ended: @escaping (CGFloat) -> Void) {
        self.changed = changed
        self.ended = ended
    }

    var gesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { changed($0.translation.height) }
            .onEnded { ended($0.translation.height) }
    }
}

extension PaperRowView where Accessory == EmptyView {
    public init(
        title: String, blocks: [TimeBlock], milestones: [Milestone] = [], overview: PaperOverview, axis: TimeAxis,
        now: Date, labelWidth: CGFloat = Theme.labelWidth,
        metrics: RowMetrics = AppSettings.RowSize.large.menuBarWindow, isDetailed: Bool = false,
        editing: BlockEditing? = nil, labelDrag: LabelDrag? = nil, trackHeight: CGFloat? = nil,
        resize: ((CGFloat?) -> Void)? = nil, card: HoverCardSource? = nil
    ) {
        self.init(
            title: title, blocks: blocks, milestones: milestones, overview: overview, axis: axis, now: now,
            labelWidth: labelWidth, metrics: metrics, isDetailed: isDetailed, editing: editing, labelDrag: labelDrag,
            trackHeight: trackHeight, resize: resize, card: card
        ) { EmptyView() }
    }
}

/// A name with an optional short line under it, for the name column of a row.
private struct RowLabel<Title: View>: View {
    let subtitle: String?
    @ViewBuilder let title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// A paper's plan with a row per kind of work, each with as many rounds as it has, its milestones
/// in a row above them and its deadlines in a row below, the flag's line running through the work
/// (paper detail and the progress email's image). While editing, the four usual kinds, the
/// milestones and the deadlines always have a row, so that a first one can be drawn in.
public struct PaperTimeline: View {
    public let blocks: [TimeBlock]
    public var milestones: [Milestone]
    public var deadlines: [TimelineDeadline]
    public let axis: TimeAxis
    public let now: Date
    public var labelWidth: CGFloat
    public var barHeight: CGFloat
    public var blockName: (TimeBlock) -> String
    public var todayLabel: String
    public var locale: Locale
    public var showsHelp: Bool
    public var milestonesLabel: String
    public var deadlinesLabel: String
    /// The kinds of work that have a row even without blocks: a paper's, or other work's.
    public var kinds: [TimeBlock.Kind]
    public var editing: BlockEditing?
    public var milestoneEditing: MilestoneEditing?
    public var deadlineEditing: DeadlineEditing?
    public var goToToday: (() -> Void)?

    /// The deadline under the pointer, whose line runs through the work while it is there.
    @State private var hoveredDeadline: String?
    @Environment(\.axisLabels) private var axisLabels

    public init(
        blocks: [TimeBlock], milestones: [Milestone] = [], deadlines: [TimelineDeadline] = [], axis: TimeAxis,
        now: Date, labelWidth: CGFloat, barHeight: CGFloat = Theme.planBarHeight,
        blockName: @escaping (TimeBlock) -> String = { $0.displayName },
        todayLabel: String = SharedText.today, milestonesLabel: String = SharedText.milestones,
        deadlinesLabel: String = SharedText.deadlines, locale: Locale = .autoupdatingCurrent,
        showsHelp: Bool = true, kinds: [TimeBlock.Kind] = BlockLane.paperKinds,
        editing: BlockEditing? = nil, milestoneEditing: MilestoneEditing? = nil,
        deadlineEditing: DeadlineEditing? = nil, goToToday: (() -> Void)? = nil
    ) {
        self.blocks = blocks
        self.milestones = milestones
        self.deadlines = deadlines
        self.axis = axis
        self.now = now
        self.labelWidth = labelWidth
        self.barHeight = barHeight
        self.blockName = blockName
        self.todayLabel = todayLabel
        self.milestonesLabel = milestonesLabel
        self.deadlinesLabel = deadlinesLabel
        self.locale = locale
        self.showsHelp = showsHelp
        self.kinds = kinds
        self.editing = editing
        self.milestoneEditing = milestoneEditing
        self.deadlineEditing = deadlineEditing
        self.goToToday = goToToday
    }

    private var rowHeight: CGFloat {
        barHeight + 16
    }

    /// The flag, and the deadline under the pointer, whose lines run through the work.
    private var lines: [TimelineDeadline] {
        deadlines.filter { ($0.style == .flag || $0.id == hoveredDeadline) && axis.contains($0.date) }
    }

    public var body: some View {
        let lanes = BlockLane.lanes(of: blocks, includingEmpty: editing?.add != nil, kinds: kinds)
        VStack(alignment: .leading, spacing: 0) {
            AxisHeader(axis: axis, now: now, todayLabel: todayLabel, locale: locale, goToToday: goToToday)
                .padding(.leading, labelWidth + Theme.Space.s)
                .padding(.bottom, 4)
            if showsMilestones {
                milestoneRow
            }
            ForEach(lanes) { lane in
                // An empty row still has a name and a color: those of the block it would get.
                let sample = lane.blocks.first ?? lane.newBlock(from: Day(now), to: Day(now))
                HStack(spacing: Theme.Space.s) {
                    LaneLabel(
                        name: blockName(sample),
                        status: lane.blocks.isEmpty ? .empty : lane.blocks.allSatisfy(\.isDone) ? .done : .open,
                        add: editing?.add.map { add in { add(lane.nextRound(today: Day(now))) } },
                        addHelp: Text("Add \(blockName(sample))", bundle: .module)
                    ) {
                        Circle()
                            .fill(
                                BlockColor.color(for: sample).opacity(
                                    !lane.blocks.isEmpty && lane.blocks.allSatisfy(\.isDone) ? 1 : Theme.undoneOpacity)
                            )
                            .frame(width: LaneLabelLayout.markerWidth, height: LaneLabelLayout.markerWidth)
                    }
                    .frame(width: labelWidth, alignment: .leading)
                    PlanBar(
                        axis: axis, now: now, blocks: lane.blocks, lines: lines.map(\.date),
                        height: PlanBar.height(for: lane.blocks, base: barHeight), baseHeight: barHeight,
                        rowShowsWholeName: showsWhole(blockName(sample)),
                        showsHelp: showsHelp, showsPeople: true, blockName: blockName,
                        editing: editing(for: lane)
                    )
                    .frame(maxHeight: .infinity)
                    .background(AxisGrid(axis: axis, now: now))
                }
                .frame(height: PlanBar.rowHeight(for: lane.blocks, base: barHeight, rowHeight: rowHeight))
            }
            if showsDeadlines {
                deadlineRow
            }
        }
        .overlay(alignment: .topLeading) {
            if !lanes.isEmpty {
                // Through the work only, as far down as today's line, so that the flag under it
                // stands on its own rather than on a long pole.
                DeadlineLines(
                    axis: axis, lines: deadlines.filter { $0.style == .flag || $0.id == hoveredDeadline }, now: now
                )
                .padding(.leading, labelWidth + Theme.Space.s)
                .padding(
                    .top,
                    AxisHeader.height(for: axisLabels.wrappedValue) + 4
                        + (showsMilestones ? Self.milestoneRowHeight : 0)
                )
                .padding(.bottom, showsDeadlines ? DeadlineTrack.height : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// While editing always, so that a first one can be added; in the email only with something in it.
    private var showsMilestones: Bool {
        milestoneEditing != nil || !milestones.isEmpty
    }

    private var showsDeadlines: Bool {
        deadlineEditing != nil || deadlines.contains { axis.contains($0.date) }
    }

    private var milestoneRow: some View {
        HStack(spacing: Theme.Space.s) {
            LaneLabel(
                name: milestonesLabel,
                status: milestones.isEmpty ? .empty : milestones.allSatisfy(\.isDone) ? .done : .open,
                add: milestoneEditing.map { editing in { editing.add(Milestone(day: Day(now).adding(7))) } },
                addHelp: Text("Add Milestone", bundle: .module)
            ) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.calm.opacity(milestones.isEmpty ? Theme.undoneOpacity : 1))
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
                    .frame(width: 8, height: 8)
            }
            .frame(width: labelWidth, alignment: .leading)
            MilestoneTrack(axis: axis, now: now, milestones: milestones, blocks: blocks, editing: milestoneEditing)
                .background(AxisGrid(axis: axis, now: now))
        }
        .frame(height: Self.milestoneRowHeight)
    }

    private var deadlineRow: some View {
        let hasFlag = deadlines.contains { $0.style == .flag }
        let hasOpen = deadlines.contains { $0.style != .closed }
        return HStack(spacing: Theme.Space.s) {
            LaneLabel(
                name: deadlinesLabel, status: deadlines.isEmpty ? .empty : hasOpen ? .open : .done,
                add: deadlineEditing.map { editing in { editing.add(nil) } },
                addHelp: Text("Add Deadline", bundle: .module)
            ) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(hasFlag ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
                    .frame(width: 8, height: 8)
            }
            .frame(width: labelWidth, alignment: .leading)
            DeadlineTrack(
                axis: axis, now: now, deadlines: deadlines, editing: deadlineEditing, hovered: $hoveredDeadline,
                leavesOutCrowded: deadlineEditing == nil)
        }
        .frame(height: DeadlineTrack.height)
    }

    static let milestoneRowHeight: CGFloat = 30

    /// Whether a row's label writes `name` out whole, after its marker and before the + it has
    /// while rounds can be added.
    private func showsWhole(_ name: String) -> Bool {
        CGFloat(TextWidth.of(name, style: .callout))
            <= LaneLabelLayout.nameRoom(in: labelWidth, canAdd: editing?.add != nil)
    }

    /// A row's blocks line up with those of the other rows, and drawing in it makes its kind.
    private func editing(for lane: BlockLane) -> BlockEditing? {
        guard var editing else { return nil }
        let ids = Set(lane.blocks.map(\.id))
        editing.otherBlocks = blocks.filter { !ids.contains($0.id) }
        editing.newBlock = { lane.newBlock(from: $0, to: $1) }
        return editing
    }
}

/// The widths a lane's label is laid out by.
private enum LaneLabelLayout {
    static let spacing: CGFloat = 7
    static let markerWidth: CGFloat = 8
    /// The width of the + button.
    static let addWidth: CGFloat = 13

    /// How wide a name can be and still be written out whole, in a label `width` points wide.
    static func nameRoom(in width: CGFloat, canAdd: Bool) -> CGFloat {
        width - markerWidth - 2 * spacing - (canAdd ? spacing + addWidth : 0)
    }
}

/// The name of a row of the timeline, with its marker; while editing, a button on hover adds
/// another round of its work, or another milestone.
private struct LaneLabel<Marker: View>: View {
    enum Status {
        case empty, open, done
    }

    let name: String
    let status: Status
    let add: (() -> Void)?
    let addHelp: Text
    @ViewBuilder let marker: Marker

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: LaneLabelLayout.spacing) {
            marker
            Text(name)
                .lineLimit(1)
                .foregroundStyle(status == .open ? .primary : status == .done ? .secondary : .tertiary)
            Spacer(minLength: 0)
            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0)
                .help(addHelp)
                .accessibilityLabel(addHelp)
            }
        }
        .font(.callout)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

/// The flag's dashed line through the work, and a gray one at the deadline under the pointer,
/// drawn from the axis frame by frame, so that they glide with the bars.
private struct DeadlineLines: View, Animatable {
    var axis: TimeAxis
    let lines: [TimelineDeadline]
    let now: Date

    nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }

    var body: some View {
        Canvas { context, size in
            for line in lines where axis.contains(line.date) {
                let x = axis.x(line.date, width: size.width)
                let path = Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                let isFlag = line.style == .flag
                context.stroke(
                    path,
                    with: isFlag
                        ? .color(.red.opacity(0.75 * line.opacity(now: now))) : .style(.secondary.opacity(0.5)),
                    style: StrokeStyle(lineWidth: isFlag ? 1.5 : 1, dash: isFlag ? [4, 3] : [3, 3]))
            }
        }
    }
}
