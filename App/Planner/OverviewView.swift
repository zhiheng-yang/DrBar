import DrBarKit
import DrBarUI
import SwiftUI

/// All papers and the items of each group on one axis, then the starred conferences: one row per
/// paper or item with blocks, its blocks as wide bars with their names and a tick at each of its
/// deadlines, the flag's in red; the deadlines of the work without blocks as flags on the line of
/// the group's name; and a thin bar per conference. Blocks can be dragged to other days, and papers
/// and items, by their names, to another place, also past a title into another group; swiping
/// sideways looks back or ahead, and pinching zooms.
struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: UUID?
    @State private var hoveredRow: String?
    /// A paper or an item being dragged by its name, among the movable rows.
    @State private var reorder: RowMove?
    /// How tall a section title is with the space above it, for the rows that make room.
    @State private var titleHeight: CGFloat = 40
    /// Set by Esc during a reorder, until the button comes up.
    @State private var isReorderCancelled = false
    @State private var cancellation = DragCancellation()
    /// The bar area in the list's coordinates, which swipes and pinches are measured against.
    @State private var track = CGRect(x: 0, y: 0, width: 600, height: 0)
    /// The block selected with a click, which the keys act on.
    @State private var selectedBlock: TimeBlock.ID?
    @FocusState private var isFocused: Bool

    static let labelWidth: CGFloat = 190

    var body: some View {
        @Bindable var store = store
        Group {
            // The starred conferences show without papers too, as in the menu bar window.
            if store.userData.papers.isEmpty && store.listedRows(since: store.plannerAxis.start).isEmpty {
                ContentUnavailableView {
                    Label("No Papers Yet", systemImage: "doc.text")
                } description: {
                    Text("Add a paper, choose its conference, and plan it backwards from the deadline.")
                } actions: {
                    Button("New Paper") { store.addItem(undoManager: undoManager) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    timeline
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .dragToPan(perform: pan)
                        // A click beside the rows lets the selected block go.
                        .contentShape(Rectangle())
                        .onTapGesture { selectedBlock = nil }
                        .focusable(interactions: .edit)
                        .focusEffectDisabled()
                        .focused($isFocused)
                        .onKeyPress(phases: [.down, .repeat], action: handleKey)
                }
                .coordinateSpace(.named(Self.timeline))
                .timelineNavigation($store.plannerPosition, track: track, now: store.now, range: store.axisRange)
                .barsGrowIn()
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItemGroup {
                ControlGroup {
                    Button {
                        step(-1)
                    } label: {
                        Label("Earlier", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.leftArrow)
                    .help("Earlier (⌘←)")
                    Button("Today") { step(0) }
                        .keyboardShortcut("t")
                        .disabled(store.plannerPosition.shift == 0)
                        .help("Today (⌘T)")
                    Button {
                        step(1)
                    } label: {
                        Label("Later", systemImage: "chevron.right")
                    }
                    .keyboardShortcut(.rightArrow)
                    .help("Later (⌘→)")
                }
                RangePicker()
            }
        }
    }

    private var timeline: some View {
        let axis = store.plannerAxis
        let sections = store.itemSections()
        let movable = sections.movableRows
        let heights = heights(of: movable, in: sections)
        let deadlines = store.listedRows(since: axis.start)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { number, section in
                if number == 0 {
                    header(Text(verbatim: section.title), axis: axis)
                    // The first title carries the axis, so its work's line comes under it.
                    if !section.unplanned.isEmpty {
                        HStack(spacing: Theme.Space.s) {
                            Color.clear
                                .frame(width: Self.labelWidth, height: Theme.laneHeight)
                            lane(section, axis: axis)
                        }
                        .padding(.bottom, 6)
                    }
                } else {
                    HStack(spacing: Theme.Space.s) {
                        sectionTitle(Text(verbatim: section.title))
                        if !section.unplanned.isEmpty {
                            lane(section, axis: axis)
                        }
                    }
                    .frame(height: Theme.laneHeight)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        titleHeight = $0
                    }
                    .reordering(movable.firstIndex(of: .heading(section.groupID)), by: reorder, heights: heights)
                }
                ForEach(section.planned) { paper in
                    let slot = movable.firstIndex(of: .item(paper.id)) ?? 0
                    row(
                        paper, axis: axis, isLifted: reorder?.from == slot,
                        drag: reorderDrag(paper.id, from: slot, in: sections, heights: heights)
                    )
                    .reordering(slot, by: reorder, heights: heights)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if !deadlines.isEmpty {
                if sections.isEmpty {
                    header(Text("Conferences"), axis: axis)
                } else {
                    sectionTitle(Text("Conferences"))
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                }
                ForEach(deadlines) { deadline in
                    row(deadline, axis: axis)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Timeline of all papers and deadlines"))
    }

    /// The first title, which carries the axis.
    private func header(_ title: Text, axis: TimeAxis) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            sectionTitle(title)
            AxisHeader(axis: axis, now: store.now) { step(0) }
                // Only across: scrolling up and down must not redraw the page.
                .onGeometryChange(for: CGRect.self) {
                    let frame = $0.frame(in: .named(Self.timeline))
                    return CGRect(x: frame.minX, y: 0, width: frame.width, height: 0)
                } action: {
                    track = $0
                }
        }
        .padding(.bottom, 10)
    }

    private func sectionTitle(_ title: Text) -> some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: Self.labelWidth, alignment: .leading)
    }

    /// The deadlines of the group's work without blocks, on one line.
    private func lane(_ section: ItemSection, axis: TimeAxis) -> some View {
        DueLane(
            work: store.dueWork(of: section), axis: axis, now: store.now,
            open: { store.plannerSelection = .paper($0) }, card: store.dueCard
        ) { id in
            if let paper = store.userData.papers.first(where: { $0.id == id }) {
                menu(for: paper, overview: store.overview(for: paper))
            }
        }
    }

    /// A starred conference, its thin bar on the same axis.
    private func row(_ deadline: DeadlineRow, axis: TimeAxis) -> some View {
        DeadlineRowView(
            row: deadline, axis: axis, now: store.now, labelWidth: Self.labelWidth,
            metrics: store.settings.rowSize.quiet, isQuiet: true, card: store.card(for: deadline, isQuiet: true)
        )
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.fill.quaternary)
                .padding(.horizontal, -10)
                .opacity(hoveredRow == deadline.id ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredRow = deadline.id
            } else if hoveredRow == deadline.id {
                hoveredRow = nil
            }
        }
        .onTapGesture { store.open(.deadline(deadline.source)) }
        .contextMenu { ConferenceRowMenu(row: deadline) { store.open(.deadline(deadline.source)) } }
    }

    private func row(_ paper: Paper, axis: TimeAxis, isLifted: Bool, drag: LabelDrag) -> some View {
        let overview = store.overview(for: paper)
        return PaperRowView(
            title: paper.displayTitle, blocks: paper.blocks, milestones: paper.milestones, overview: overview,
            axis: axis, now: store.now, labelWidth: Self.labelWidth, metrics: store.settings.rowSize.planner,
            isDetailed: true,
            editing: BlockEditing(
                cutoffs: overview.cutoffs, deadlineDays: overview.deadlines.days(), selection: selectedBlock,
                commit: { block, handle in store.drag(block, handle, in: paper.id, undoManager: undoManager) },
                select: { id in
                    selectedBlock = id
                    $isFocused.takeKeys()
                },
                open: { block in store.editBlock(block.id, of: paper.id) },
                toggleDone: { block in
                    animated { store.setDone(!block.isDone, ofBlock: block.id, in: paper.id, undoManager: undoManager) }
                },
                delete: delete, pan: pan),
            labelDrag: drag,
            trackHeight: paper.trackHeight.map { CGFloat($0) },
            resize: { height in store.setTrackHeight(height.map(Double.init), of: paper.id, undoManager: undoManager) },
            card: store.card(for: paper, overview: overview)
        )
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isLifted ? AnyShapeStyle(.background) : AnyShapeStyle(.fill.quaternary))
                .shadow(color: .black.opacity(isLifted ? 0.18 : 0), radius: 8, y: 3)
                .padding(.horizontal, -10)
                .opacity(isLifted || (hovered == paper.id && reorder == nil) ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hovered = paper.id
            } else if hovered == paper.id {
                hovered = nil
            }
        }
        .onTapGesture { store.plannerSelection = .paper(paper.id) }
        .contextMenu { menu(for: paper, overview: overview) }
    }

    /// What can be done with a paper or an item, from its row or its flag.
    @ViewBuilder
    private func menu(for paper: Paper, overview: PaperOverview) -> some View {
        Button("Open") { store.plannerSelection = .paper(paper.id) }
        if !paper.isPaper, overview.currentBlock == nil {
            Button("Mark as Done") {
                animated { store.setDone(true, ofItem: paper.id, undoManager: undoManager) }
            }
        }
        if paper.blocks.isEmpty, let deadline = overview.planningDeadline {
            Button("Plan Backwards from Deadline") {
                let fits = withAnimation(reduceMotion ? nil : .settle) {
                    store.planBackwards(paper.id, to: deadline, undoManager: undoManager)
                }
                // Without enough time, its page says so, where the plan is adjusted.
                if !fits {
                    store.tightPlanRequest = paper.id
                    store.plannerSelection = .paper(paper.id)
                }
            }
        }
        if paper.isPaper {
            Button("Send Progress…") { store.requestSend(paper.id) }
        }
        Toggle("Show in Menu Bar", isOn: store.showsInMenuBar(.paper(paper.id)))
        Button("Archive") { animated { store.archive(paper.id, undoManager: undoManager) } }
        Divider()
        Button(paper.isPaper ? "Delete Paper" : "Delete Item", role: .destructive) {
            animated { store.deletePaper(paper.id, undoManager: undoManager) }
        }
    }

    /// Dragging a paper or an item by its name: it follows the pointer, the rows and titles it
    /// passes make room, and on release it settles into its new place, in the group it was dragged
    /// into.
    private func reorderDrag(_ id: UUID, from slot: Int, in sections: [ItemSection], heights: [Double]) -> LabelDrag {
        LabelDrag(
            changed: { translation in
                guard !isReorderCancelled else { return }
                cancellation.listen {
                    reorder = nil
                    isReorderCancelled = true
                }
                reorder = RowMove(from: slot, translation: translation)
            },
            ended: { translation in
                cancellation.stop()
                guard !isReorderCancelled else {
                    isReorderCancelled = false
                    return
                }
                let move = RowMove(from: slot, translation: translation)
                withAnimation(reduceMotion ? nil : .drop) {
                    reorder?.translation = move.landing(heights: heights)
                } completion: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        reorder = nil
                        store.drop(id, at: move.destination(heights: heights), in: sections, undoManager: undoManager)
                    }
                }
            })
    }

    /// How tall each movable row is: a title with the space above it, or a paper's row.
    private func heights(of rows: [SidebarRow], in sections: [ItemSection]) -> [Double] {
        let papers = Dictionary(sections.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let metrics = store.settings.rowSize.planner
        return rows.map { row in
            guard case let .item(id) = row, let paper = papers[id] else { return Double(titleHeight) }
            return Double(metrics.paperRowHeight(for: paper.blocks, trackHeight: paper.trackHeight.map { CGFloat($0) }))
        }
    }

    nonisolated private static let timeline = "timeline"

    /// The bars follow a swipe or a drag of `points`.
    private func pan(_ points: CGFloat) {
        store.plannerPosition.pan(by: points, width: track.width, now: store.now, range: store.axisRange)
    }

    /// With a block selected: Delete moves it, and only it, to Recently Deleted, Return opens it on
    /// its paper's page, Esc lets it go, and the arrow keys slide it by a day, or by a week with
    /// Shift.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let id = selectedBlock, !press.modifiers.contains(.command) else { return .ignored }
        guard let (paperID, block) = store.block(id) else {
            selectedBlock = nil
            return .ignored
        }
        switch press.key {
        case .delete, .deleteForward: delete(block)
        case .return: store.editBlock(block.id, of: paperID)
        case .escape: selectedBlock = nil
        case .leftArrow, .rightArrow:
            let days = (press.modifiers.contains(.shift) ? 7 : 1) * (press.key == .leftArrow ? -1 : 1)
            withAnimation(reduceMotion ? nil : .glide) {
                store.drag(block.dragged(.body, by: days), .body, in: paperID, undoManager: undoManager)
            }
        default: return .ignored
        }
        return .handled
    }

    private func delete(_ block: TimeBlock) {
        if selectedBlock == block.id {
            selectedBlock = nil
        }
        animated { store.deleteBlock(block.id, undoManager: undoManager) }
    }

    /// A row that leaves, archived or deleted, slides away and the rows below close up.
    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .settle, change)
    }

    /// ‹ and › move the axis by a step; 0 goes back to today.
    private func step(_ direction: Int) {
        withAnimation(reduceMotion ? nil : .glide) {
            if direction == 0 {
                store.plannerPosition.shift = 0
            } else {
                store.plannerPosition.step(direction, now: store.now, range: store.axisRange)
            }
        }
    }
}
