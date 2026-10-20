import DrBarKit
import DrBarUI
import SwiftUI

/// The window under the menu bar item: a small Gantt chart of the papers and the deadlines,
/// framed like the system's own menu bar extras, with a title and a few menu rows at the bottom.
/// Swiping sideways looks back or ahead; blocks and papers can be dragged as in the planner.
struct PopoverView: View {
    enum Page: Equatable {
        case home
        case detail(DeadlineRow.Source)
    }

    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page

    init(page: Page = .home) {
        _page = State(initialValue: page)
    }

    static let width: CGFloat = 640
    static let maxContentHeight: CGFloat = 600
    /// Left and right margin.
    static let margin: CGFloat = 18

    var body: some View {
        // The page that comes in fades in from the side it comes from; the one it replaces goes at
        // once, so that the window changes its size only once.
        ZStack(alignment: .top) {
            switch page {
            case .home:
                HomePage(open: { page = $0 }, openSettings: openSettingsWindow)
                    .transition(.page(from: reduceMotion ? nil : .leading))
            case let .detail(source):
                DeadlineDetailView(source: source, onBack: { page = .home })
                    .transition(.page(from: reduceMotion ? nil : .trailing))
            }
        }
        .animation(.page, value: page)
        // A new day moves everything a day to the left.
        .animation(reduceMotion ? nil : .glide, value: Day(store.now))
        .frame(width: Self.width)
        .hoverCardHost()
        .background(alignment: .topLeading) { shortcuts }
        // It opens again on today and the chosen range, even if it was never clicked.
        .onDisappear { store.popoverPosition = AxisPosition() }
    }

    /// Keyboard shortcuts without visible buttons, as in a menu.
    private var shortcuts: some View {
        Group {
            Button("Settings") { openSettingsWindow() }
                .keyboardShortcut(",")
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
            Button("Find") { store.open(.conferences) }
                .keyboardShortcut("f")
            Button("Back") { page = .home }
                .keyboardShortcut(.cancelAction)
                .disabled(page == .home)
            Group {
                Button("Undo") { undoManager?.undo() }
                    .keyboardShortcut("z")
                Button("Redo") { undoManager?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Button("Earlier") { step(-1) }
                    .keyboardShortcut(.leftArrow)
                Button("Later") { step(1) }
                    .keyboardShortcut(.rightArrow)
                Button("Today") { step(0) }
                    .keyboardShortcut("t")
                Button("Zoom In") { zoom(by: 1.5) }
                    .keyboardShortcut("=")
                Button("Zoom Out") { zoom(by: 1 / 1.5) }
                    .keyboardShortcut("-")
                Button("Actual Size") { zoom(to: 1) }
                    .keyboardShortcut("0")
            }
            .disabled(page != .home)
        }
        .hidden()
        .accessibilityHidden(true)
    }

    /// ⌘← and ⌘→ move the axis by a step; ⌘T goes back to today.
    private func step(_ direction: Int) {
        withAnimation(reduceMotion ? nil : .glide) {
            if direction == 0 {
                store.popoverPosition.shift = 0
            } else {
                store.popoverPosition.step(direction, now: store.now, range: store.axisRange)
            }
        }
    }

    /// ⌘+ and ⌘− zoom around today, or the middle when today is out of sight; ⌘0 goes back to the
    /// chosen range.
    private func zoom(by factor: Double) {
        zoom(to: store.popoverPosition.zoom * factor)
    }

    private func zoom(to level: Double) {
        withAnimation(reduceMotion ? nil : .glide) {
            store.popoverPosition.zoom(to: level, now: store.now, range: store.axisRange)
        }
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate()
    }
}

/// Papers and deadlines on one shared axis, papers first.
private struct HomePage: View {
    let open: (PopoverView.Page) -> Void
    let openSettings: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @State private var hovered: String?
    @State private var checks: [UUID: Int] = [:]
    /// The bar area in the list's coordinates, which swipes and pinches are measured against.
    @State private var track = CGRect(
        x: PopoverView.margin + Theme.labelWidth + Theme.Space.s, y: 0,
        width: PopoverView.width - 2 * PopoverView.margin - Theme.labelWidth - Theme.Space.s, height: 0)
    /// A paper or an item being dragged by its name, among the movable rows.
    @State private var reorder: RowMove?
    /// How tall a section header is with the space above it, for the rows that make room.
    @State private var headerHeight: CGFloat = 30
    /// Set by Esc during a reorder, until the button comes up.
    @State private var isReorderCancelled = false
    @State private var cancellation = DragCancellation()
    /// The block selected with a click, which the keys act on.
    @State private var selectedBlock: TimeBlock.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var store = store
        let sections = store.itemSections(hidesFinished: true)
        let rows = store.listedRows(since: store.popoverAxis.start)
        let axis = store.popoverAxis
        VStack(spacing: 0) {
            header
            if !store.catalogLoaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if sections.isEmpty && store.userData.favoriteSeries.isEmpty {
                welcome
            } else {
                FittingScrollView(maxHeight: PopoverView.maxContentHeight) {
                    VStack(alignment: .leading, spacing: 0) {
                        let movable = sections.movableRows
                        let heights = heights(of: movable, in: sections)
                        ForEach(Array(sections.enumerated()), id: \.element.id) { number, section in
                            if number == 0 {
                                sectionHeader(Text(verbatim: section.title), axis: axis)
                                // The first title carries the axis, so its work's line comes under it.
                                if !section.unplanned.isEmpty {
                                    HStack(spacing: Theme.Space.s) {
                                        Color.clear
                                            .frame(width: Theme.labelWidth, height: Theme.laneHeight)
                                        lane(section, axis: axis)
                                    }
                                    .padding(.horizontal, PopoverView.margin)
                                    .padding(.bottom, 4)
                                }
                            } else {
                                sectionHeader(Text(verbatim: section.title), axis: nil, lane: section)
                                    .padding(.top, 8)
                                    .onGeometryChange(for: CGFloat.self) {
                                        $0.size.height
                                    } action: {
                                        headerHeight = $0
                                    }
                                    .reordering(
                                        movable.firstIndex(of: .heading(section.groupID)), by: reorder, heights: heights
                                    )
                            }
                            ForEach(section.planned) { paper in
                                let slot = movable.firstIndex(of: .item(paper.id)) ?? 0
                                paperRow(
                                    paper, axis: axis, isLifted: reorder?.from == slot,
                                    drag: reorderDrag(paper.id, from: slot, in: sections, heights: heights)
                                )
                                .reordering(slot, by: reorder, heights: heights)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                        if !rows.isEmpty || sections.isEmpty {
                            sectionHeader(Text("Conferences"), axis: sections.isEmpty ? axis : nil)
                                .padding(.top, sections.isEmpty ? 0 : 8)
                            if rows.isEmpty {
                                // Starred, with nothing announced ahead.
                                hint(Text("No Upcoming Deadlines"))
                            }
                            // Under papers and groups, the conferences are thin and quiet.
                            ForEach(rows) { row in
                                deadlineRow(row, axis: axis, isQuiet: !sections.isEmpty)
                            }
                        }
                    }
                    .padding(.bottom, 6)
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
                .timelineNavigation($store.popoverPosition, track: track, now: store.now, range: store.axisRange)
                .barsGrowIn()
            }
            MenuDivider()
            footer
        }
        // Opened again, the window starts with nothing selected.
        .onDisappear { selectedBlock = nil }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text(verbatim: "DrBar")
                .font(.headline)
            Spacer()
            if let problem = store.saveError ?? store.dataNotice {
                Button {
                    store.open(.planner)
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help(problem)
            }
            switch store.syncActivity {
            case .syncing:
                ProgressView()
                    .controlSize(.mini)
                    .help(SyncStatusText.text(for: store))
            case let .failed(offline):
                Image(systemName: offline ? "wifi.slash" : "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .help(SyncStatusText.text(for: store))
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, PopoverView.margin)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRow(title: Text("Browse Conferences…"), shortcut: "⌘F") { store.open(.conferences) }
            MenuRow(title: Text("Open Planner…")) { store.open(.planner) }
            MenuDivider()
            MenuRow(title: Text("Settings…"), shortcut: "⌘,", action: openSettings)
            MenuRow(title: Text("Quit DrBar"), shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .padding(.bottom, 5)
    }

    /// Small and grey, like the section headers of the Wi-Fi and Bluetooth menus, in the name
    /// column. The first one carries the axis labels; the others, the deadlines of their work
    /// without blocks.
    private func sectionHeader(_ title: Text, axis: TimeAxis?, lane section: ItemSection? = nil) -> some View {
        // With the axis, level with its first line, which a second one may follow.
        HStack(alignment: axis == nil ? .center : .top, spacing: Theme.Space.s) {
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: Theme.labelWidth, alignment: .leading)
            if let axis {
                AxisHeader(axis: axis, now: store.now, goToToday: goToToday)
                    // Only across: scrolling up and down must not redraw the list.
                    .onGeometryChange(for: CGRect.self) {
                        let frame = $0.frame(in: .named(Self.timeline))
                        return CGRect(x: frame.minX, y: 0, width: frame.width, height: 0)
                    } action: {
                        track = $0
                    }
            } else if let section, !section.unplanned.isEmpty {
                lane(section, axis: store.popoverAxis)
            }
        }
        .frame(height: axis == nil ? Theme.laneHeight : nil)
        .padding(.horizontal, PopoverView.margin)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// The deadlines of the group's work without blocks, on one line.
    private func lane(_ section: ItemSection, axis: TimeAxis) -> some View {
        DueLane(
            work: store.dueWork(of: section), axis: axis, now: store.now, open: { store.open(.paper($0)) },
            card: store.dueCard
        ) { id in
            if let paper = store.userData.papers.first(where: { $0.id == id }) {
                menu(for: paper, overview: store.overview(for: paper))
            }
        }
    }

    private func goToToday() {
        withAnimation(reduceMotion ? nil : .glide) { store.popoverPosition.shift = 0 }
    }

    nonisolated private static let timeline = "timeline"

    /// The bars follow a swipe or a drag of `points`.
    private func pan(_ points: CGFloat) {
        store.popoverPosition.pan(by: points, width: track.width, now: store.now, range: store.axisRange)
    }

    private func hint(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, PopoverView.margin)
            .padding(.vertical, 8)
    }

    private var welcome: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "graduationcap")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("Follow a conference")
                .font(.headline)
            Text("Star the conferences you submit to, and their deadlines appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
    }

    // MARK: Rows

    private func deadlineRow(_ row: DeadlineRow, axis: TimeAxis, isQuiet: Bool) -> some View {
        let size = store.settings.rowSize
        return DeadlineListRow(
            row: row, axis: axis, isQuiet: isQuiet, metrics: isQuiet ? size.quiet : size.menuBarWindow
        ) { select(row) }
        .contextMenu { ConferenceRowMenu(row: row) { select(row) } }
        .accessibilityAction(named: Text("Show Details")) { select(row) }
    }

    /// A paper or an item: its blocks can be dragged to other days, and the row itself, by its
    /// name, to another place, also into another group.
    private func paperRow(_ paper: Paper, axis: TimeAxis, isLifted: Bool, drag: LabelDrag) -> some View {
        let overview = store.overview(for: paper)
        let id = paper.id.uuidString
        return PaperRowView(
            title: paper.displayTitle, blocks: paper.blocks, milestones: paper.milestones, overview: overview,
            axis: axis, now: store.now, metrics: store.settings.rowSize.menuBarWindow, isDetailed: true,
            editing: BlockEditing(
                cutoffs: overview.cutoffs, deadlineDays: overview.deadlines.days(), selection: selectedBlock,
                commit: { block, handle in store.drag(block, handle, in: paper.id, undoManager: undoManager) },
                select: { id in
                    selectedBlock = id
                    $isFocused.takeKeys()
                },
                open: { block in store.editBlock(block.id, of: paper.id) },
                toggleDone: { block in
                    withAnimation(reduceMotion ? nil : .glide) {
                        store.setDone(!block.isDone, ofBlock: block.id, in: paper.id, undoManager: undoManager)
                    }
                },
                delete: delete, pan: pan),
            labelDrag: drag, card: store.card(for: paper, overview: overview)
        ) {
            if hovered == id, reorder == nil, let block = overview.currentBlock {
                Button {
                    markDone(paper)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .symbolEffect(.bounce, value: checks[paper.id, default: 0])
                }
                .buttonStyle(.borderless)
                .help(Text("Mark “\(block.displayName)” done"))
            }
        }
        .rowChrome(isHovered: hovered == id && reorder == nil, isLifted: isLifted)
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        .onTapGesture { store.open(.paper(paper.id)) }
        .contextMenu { menu(for: paper, overview: overview) }
        .accessibilityAction(named: Text("Open in Planner")) { store.open(.paper(paper.id)) }
    }

    /// What can be done with a paper or an item, from its row or its flag.
    @ViewBuilder
    private func menu(for paper: Paper, overview: PaperOverview) -> some View {
        Button("Open in Planner") { store.open(.paper(paper.id)) }
        if let block = overview.currentBlock {
            Button("Mark “\(block.displayName)” Done") { markDone(paper) }
        } else if !paper.isPaper {
            Button("Mark as Done") {
                withAnimation(reduceMotion ? nil : .settle) {
                    store.setDone(true, ofItem: paper.id, undoManager: undoManager)
                }
            }
        }
        Divider()
        if paper.isPaper {
            Button("Send Progress…") { store.requestSend(paper.id) }
        }
        Toggle("Show in Menu Bar", isOn: store.showsInMenuBar(.paper(paper.id)))
        Divider()
        Button("Archive") {
            withAnimation(reduceMotion ? nil : .settle) {
                store.archive(paper.id, undoManager: undoManager)
            }
        }
        Button(paper.isPaper ? "Delete Paper" : "Delete Item", role: .destructive) {
            withAnimation(reduceMotion ? nil : .settle) {
                store.deletePaper(paper.id, undoManager: undoManager)
            }
        }
    }

    /// How tall each movable row is: a section header with the space above it, or a paper's row,
    /// taller where blocks share days in large rows.
    private func heights(of rows: [SidebarRow], in sections: [ItemSection]) -> [Double] {
        let papers = Dictionary(sections.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let metrics = store.settings.rowSize.menuBarWindow
        return rows.map { row in
            guard case let .item(id) = row, let paper = papers[id] else { return Double(headerHeight) }
            return Double(metrics.paperRowHeight(for: paper.blocks))
        }
    }

    /// Dragging a paper or an item by its name: it follows the pointer, the rows and headers it
    /// passes make room, and on release it settles into its new place, in the group it was dragged
    /// into. Finished work that is not shown keeps its place.
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

    private func select(_ row: DeadlineRow) {
        open(.detail(row.source))
    }

    /// With a block selected: Delete moves it, and only it, to Recently Deleted, Return opens it in
    /// the planner, Esc lets it go, and the arrow keys slide it by a day, or by a week with Shift.
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
        withAnimation(reduceMotion ? nil : .settle) { store.deleteBlock(block.id, undoManager: undoManager) }
    }

    private func markDone(_ paper: Paper) {
        withAnimation(reduceMotion ? nil : .glide) {
            store.markCurrentBlockDone(paperID: paper.id, undoManager: undoManager)
        }
        if !reduceMotion {
            checks[paper.id, default: 0] += 1
        }
    }
}

/// A full-width row that acts like a menu item: plain text, the shortcut on the right, and a
/// highlight under the pointer.
struct MenuRow: View {
    let title: Text
    var shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                title
                Spacer()
                if let shortcut {
                    Text(verbatim: shortcut)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.fill.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
    }
}

/// The separator between groups of a menu.
struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, PopoverView.margin)
            .padding(.vertical, 5)
    }
}

extension View {
    /// Margins and a soft highlight under the pointer, like a menu item. No vertical padding, so
    /// the grid lines of the rows join up. A row being dragged to another place lifts off the list.
    func rowChrome(isHovered: Bool, isLifted: Bool = false) -> some View {
        padding(.horizontal, PopoverView.margin)
            .background {
                if isLifted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .padding(.horizontal, 8)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.fill.quaternary)
                        .padding(.horizontal, 8)
                        .opacity(isHovered ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
    }
}

/// A scroll view as tall as its content, up to a maximum. Menu bar windows size themselves to
/// their content, and a plain scroll view has no natural height.
struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 200

    var body: some View {
        ScrollView {
            content
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: HeightKey.self, value: geo.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
#Preview("Menu bar window") {
    DemoPreview { PopoverView() }
}

#Preview("Deadline details") {
    DemoPreview {
        let store = AppStore.shared
        if let row = store.listedRows(since: store.axis.start).first(where: { $0.name == "CVPR" }) {
            PopoverView(page: .detail(row.source))
        }
    }
}
#endif
