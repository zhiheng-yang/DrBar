import DrBarKit
import DrBarUI
import SwiftUI

/// One paper, or an item of another group: a title, the plan with its milestones above a row per
/// kind of work and its deadlines below, the lists of blocks, milestones and deadlines, the to-dos,
/// and the rest folded away. The timeline works much as Calendar does: drag across empty days to
/// draw a block, drag a block or its ends to change its days, click one to select it and
/// double-click it to edit it; milestones and deadlines of its own drag the same way. Only a paper
/// has stages and sends progress; an item is simply done or not. One in the Archive is shown as it
/// was, to look at, until it is moved back.
struct PaperDetailView: View {
    @Binding var paper: Paper

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingReplacePlan = false
    @State private var planNotice: String?
    /// The block or milestone whose editor is open, at its row or on the timeline.
    @State private var editor: EditorRequest?
    /// The deadline whose editor or details are open, at its row or at its flag.
    @State private var deadlineRequest: DeadlineRequest?
    /// The block, milestone or own deadline selected in the timeline, which the keyboard acts on.
    @State private var selection: UUID?
    /// The bar area in the timeline's coordinates, which swipes and pinches are measured against.
    @State private var track = CGRect(x: 0, y: 0, width: 600, height: 0)
    /// Where the bar, diamond or flag of the editor open on the timeline was last drawn, which the
    /// editor keeps pointing at while it is out of sight, as when its date is changed far away.
    @State private var editorAnchor = CGRect.zero
    @State private var deadlineAnchor = CGRect.zero
    /// How many plans have been made backwards from the deadline here.
    @State private var backwardPlans = 0
    @FocusState private var titleFocused: Bool
    @FocusState private var timelineFocused: Bool
    @AppStorage("paperDetailsExpanded") private var detailsExpanded = false

    private static let labelWidth: CGFloat = 140

    var body: some View {
        let overview = store.overview(for: paper)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(overview)
                    timelineCard(overview)
                    blocks(overview)
                    milestones
                    deadlines(overview)
                    todos
                    details
                }
                .disabled(isArchived)
                .hoverCardsDisabled(editor != nil || deadlineRequest != nil)
                .padding(.horizontal, 32)
                .padding(.vertical, 26)
                .frame(maxWidth: 1000, alignment: .leading)
            }
            // An editor at a row, which may be out of sight.
            .onChange(of: editor) { _, editor in
                if let editor, editor.anchor == .list {
                    withAnimation(reduceMotion ? nil : .glide) { proxy.scrollTo(editor.id) }
                }
            }
            .onChange(of: deadlineRequest) { _, request in
                if let request, request.anchor == .list {
                    withAnimation(reduceMotion ? nil : .glide) { proxy.scrollTo(request.id) }
                }
            }
        }
        .navigationTitle(paper.displayTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                RangePicker()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if isArchived {
                    Button {
                        store.unarchive([paper.id], undoManager: undoManager)
                    } label: {
                        Label("Move Back", systemImage: "arrow.uturn.backward")
                    }
                    .help("Move back to its group, to work on it again")
                } else {
                    visibleTo
                    if paper.isPaper {
                        sendProgress
                    }
                }
            }
        }
        .confirmationDialog("Replace the current plan?", isPresented: $confirmingReplacePlan) {
            Button("Replace", role: .destructive) { planBackwards(from: overview.planningDeadline) }
        } message: {
            Text("Your current time blocks will be removed.")
        }
        .onAppear(perform: openRequestedBlock)
        .onChange(of: store.blockRequest) { openRequestedBlock() }
        .onAppear(perform: showTightPlan)
        .onChange(of: store.tightPlanRequest) { showTightPlan() }
        .task {
            // A new paper starts with its title selected, ready to be typed over.
            if store.focusRequest == paper.id {
                store.focusRequest = nil
                titleFocused = true
            }
        }
    }

    /// Who may hear about this paper or item in the updates of the others: filled in once someone
    /// may.
    private var visibleTo: some View {
        let names = store.userData.mail.groups.flatMap(\.recipients)
            .filter { paper.visibleTo.contains($0.id) }.map(\.displayName)
        let list = names.formatted(.list(type: .and))
        return Menu {
            VisibleToItems(paper: paper)
        } label: {
            Label("Visible To", systemImage: names.isEmpty ? "person.2" : "person.2.fill")
        }
        .help(names.isEmpty ? Text("Visible only to you") : Text("Visible to \(list)"))
        .accessibilityValue(names.isEmpty ? Text("Only you") : Text(list))
    }

    /// When the last update went, and the button for the next one.
    @ViewBuilder
    private var sendProgress: some View {
        if let sent = store.sentNote, sent.paperID == paper.id {
            Label("Sent to \(sent.groupName)", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
        } else if let last = paper.lastSentAt {
            Text("Last sent \(SyncStatusText.relative(last, to: store.now))")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        Button {
            store.requestSend(paper.id)
        } label: {
            Label("Send Progress", systemImage: "paperplane")
        }
        .help("Email this paper's timeline")
    }

    // MARK: Header

    private func header(_ overview: PaperOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "Title", text: $paper.title, prompt: paper.isPaper ? Text("Untitled paper") : Text("Untitled item")
            )
            .textFieldStyle(.plain)
            .font(.system(size: 26, weight: .semibold))
            .focused($titleFocused)
            HStack(spacing: 14) {
                if let archivedAt = paper.archivedAt {
                    Label {
                        Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                    .foregroundStyle(.secondary)
                }
                TargetButton(paper: paper)
                if paper.isPaper {
                    Picker("Stage", selection: stage) {
                        ForEach(Paper.Stage.allCases, id: \.self) { stage in
                            Text(stage.localizedName).tag(stage)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Toggle("Done", isOn: isDone)
                        .toggleStyle(.checkbox)
                        .help("Done items leave the menu bar window")
                }
                if let symbol = overview.status.symbolName {
                    Label(overview.status.localizedDescription, systemImage: symbol)
                        .foregroundStyle(overview.status.color)
                } else if overview.deadlineNotAnnounced {
                    Text(SharedText.deadlineNotAnnounced)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    // MARK: Timeline

    private func timelineCard(_ overview: PaperOverview) -> some View {
        @Bindable var store = store
        return VStack(spacing: Theme.Space.l) {
            PaperTimeline(
                blocks: paper.blocks, milestones: paper.milestones,
                deadlines: overview.deadlines.timeline(now: store.now), axis: store.plannerAxis, now: store.now,
                labelWidth: Self.labelWidth, barHeight: 30,
                kinds: paper.isPaper ? BlockLane.paperKinds : BlockLane.workKinds, editing: editing(overview),
                milestoneEditing: milestoneEditing(overview), deadlineEditing: deadlineEditing(overview),
                goToToday: { withAnimation(reduceMotion ? nil : .glide) { store.plannerPosition.shift = 0 } }
            )
            // Each plan made backwards grows in from today, as the plan does when the page opens.
            .barsGrowIn()
            .id(backwardPlans)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { width in
                // The bars start after the name column, as in every timeline.
                let leading = Self.labelWidth + Theme.Space.s
                track = CGRect(x: leading, y: 0, width: width - leading, height: 0)
            }
            .overlayPreferenceValue(TimelineBounds.self, timelineEditor)
            .overlayPreferenceValue(DeadlineBounds.self) { deadlinePopover($0, overview: overview) }
            // Empty days draw blocks; the dates above them move the axis.
            .dragToPan(perform: pan)
            .timelineNavigation($store.plannerPosition, track: track, now: store.now, range: store.axisRange)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Timeline of the plan"))
            // Nothing is left to plan for once the main deadline is done.
            if paper.blocks.isEmpty, overview.deadlines.main?.isDone != true {
                Button("Plan Backwards from Deadline") { planBackwards(from: overview.planningDeadline) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(overview.planningDeadline == nil)
                    .help(planBackwardsHelp(overview))
            }
        }
        .padding(20)
        // A click takes the focus, as in a text field, so that the keys act on the selection.
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($timelineFocused)
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .background(alignment: .topLeading) {
            Button("Duplicate") {
                if let block = selectedBlock {
                    withAnimation(reduceMotion ? nil : .settle) { add(block.nextRound()) }
                }
            }
            .keyboardShortcut("d")
            .disabled(selectedBlock == nil || !timelineFocused)
            .hidden()
            .accessibilityHidden(true)
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    // MARK: Blocks

    private func blocks(_ overview: PaperOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Blocks")
                    .font(.headline)
                Spacer()
                if let notice = planNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                if !paper.blocks.isEmpty {
                    Menu {
                        Button("Plan Backwards from Deadline…") { confirmingReplacePlan = true }
                            .disabled(overview.planningDeadline == nil)
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Plan backwards from the deadline")
                }
                Button(action: addBlock) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Block")
            }
            if !paper.blocks.isEmpty {
                BlockListView(blocks: $paper.blocks, paperID: paper.id, editor: $editor, selection: $selection)
            }
        }
    }

    // MARK: Milestones

    private var milestones: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Milestones")
                    .font(.headline)
                Spacer()
                Button {
                    addMilestone(Milestone(day: Day(store.now).adding(7)), from: .list)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Milestone")
            }
            if !paper.milestones.isEmpty {
                MilestoneListView(
                    milestones: $paper.milestones, blocks: paper.blocks, paperID: paper.id, editor: $editor,
                    selection: $selection)
            }
        }
    }

    // MARK: Deadlines

    private func deadlines(_ overview: PaperOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(SharedText.deadlines)
                    .font(.headline)
                Spacer()
                Button {
                    addDeadline(on: nil, at: .list)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Deadline")
            }
            if !overview.deadlines.all.isEmpty {
                DeadlineListView(
                    deadlines: overview.deadlines, paperID: paper.id, editing: deadlineEditing(overview, at: .list),
                    request: $deadlineRequest, selection: $selection)
            }
        }
    }

    // MARK: To-dos

    private var todos: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("To Do")
                    .font(.headline)
                Spacer()
                if paper.todos.contains(where: \.isDone) {
                    Button("Clear Done") {
                        withAnimation(reduceMotion ? nil : .settle) {
                            store.clearDoneTodos(in: paper.id, undoManager: undoManager)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            TodoListView(todos: $paper.todos, paperID: paper.id)
        }
    }

    // MARK: Details

    private var details: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Overleaf").foregroundStyle(.secondary)
                    LinkField("Overleaf", text: $paper.overleafURL, prompt: "https://www.overleaf.com/project/…")
                }
                GridRow {
                    Text("GitHub").foregroundStyle(.secondary)
                    LinkField("GitHub", text: $paper.githubURL, prompt: "https://github.com/…")
                }
                GridRow(alignment: .top) {
                    Text("Notes").foregroundStyle(.secondary)
                    TextField("Notes", text: $paper.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .padding(.top, 10)
        } label: {
            Text("Details")
                .font(.headline)
        }
    }

    // MARK: Actions

    /// A week after the last block, or from today; its editor opens right away.
    private func addBlock() {
        let start = paper.blocks.map { $0.end.adding(1) }.max().map { max($0, Day(store.now)) } ?? Day(store.now)
        let block = TimeBlock(
            kind: .custom, customName: String(localized: "New block"), start: start, end: start.adding(6))
        store.addBlock(block, to: paper.id, undoManager: undoManager)
        selection = block.id
        editor = EditorRequest(id: block.id, anchor: .list)
    }

    private var isArchived: Bool {
        paper.archivedAt != nil
    }

    private var stage: Binding<Paper.Stage> {
        Binding(
            get: { paper.stage },
            set: { stage in
                withAnimation(reduceMotion ? nil : .glide) {
                    store.setStage(
                        stage, of: paper.id, actionName: String(localized: "Change Stage"), undoManager: undoManager)
                }
            })
    }

    /// An item has no stages but these two.
    private var isDone: Binding<Bool> {
        Binding(
            get: { paper.isFinished },
            set: { isDone in
                withAnimation(reduceMotion ? nil : .glide) {
                    store.setDone(isDone, ofItem: paper.id, undoManager: undoManager)
                }
            })
    }

    private func planBackwardsHelp(_ overview: PaperOverview) -> Text {
        if overview.planningDeadline != nil {
            return paper.isPaper
                ? Text("Writing, internal review and a buffer before the deadline, with experiments until then.")
                : Text("Writing, internal review and a buffer before the deadline.")
        }
        if overview.deadlineNotAnnounced {
            return Text(SharedText.deadlineNotAnnounced)
        }
        return paper.isPaper
            ? Text("Choose a conference with an announced deadline first.") : Text("Set a deadline first.")
    }

    /// Generates the default blocks once; they are never moved automatically afterwards.
    private func planBackwards(from deadline: Date?) {
        guard let deadline else { return }
        let fits = store.planBackwards(paper.id, to: deadline, undoManager: undoManager)
        backwardPlans += 1
        planNotice = fits ? nil : Self.tightPlanNotice
    }

    static var tightPlanNotice: String {
        String(localized: "Not enough time — please adjust by hand.")
    }

    /// A plan made from the overview without enough time is said so here, where it is adjusted.
    private func showTightPlan() {
        guard store.tightPlanRequest == paper.id else { return }
        store.tightPlanRequest = nil
        planNotice = Self.tightPlanNotice
    }

    /// The bars follow a swipe or a drag of `points`.
    private func pan(_ points: CGFloat) {
        store.plannerPosition.pan(by: points, width: track.width, now: store.now, range: store.axisRange)
    }

    // MARK: Editing on the timeline

    /// The bars: drag them to other days or draw new ones, click one to select it, double-click
    /// to edit it, right-click for more.
    private func editing(_ overview: PaperOverview) -> BlockEditing {
        BlockEditing(
            cutoffs: overview.cutoffs, deadlineDays: overview.deadlines.days(), selection: selection,
            commit: { block, handle in store.drag(block, handle, in: paper.id, undoManager: undoManager) },
            add: add,
            select: { id in
                selection = id
                $timelineFocused.takeKeys()
            },
            open: open,
            toggleDone: { block in
                withAnimation(reduceMotion ? nil : .glide) {
                    store.setDone(!block.isDone, ofBlock: block.id, in: paper.id, undoManager: undoManager)
                }
            },
            delete: delete, pan: pan, people: store.everyone,
            togglePerson: { block, person in
                store.togglePerson(person, onBlock: block.id, in: paper.id, undoManager: undoManager)
            })
    }

    private var selectedBlock: TimeBlock? {
        paper.blocks.first { $0.id == selection }
    }

    private var selectedMilestone: Milestone? {
        paper.milestones.first { $0.id == selection }
    }

    /// The diamonds: drag them to other days, click one to select it, double-click to edit it,
    /// double-click an empty day to add one.
    private func milestoneEditing(_ overview: PaperOverview) -> MilestoneEditing {
        MilestoneEditing(
            cutoffs: overview.cutoffs, deadlineDays: overview.deadlines.days(), blocks: paper.blocks,
            selection: selection,
            commit: { store.moveMilestone($0.id, to: $0.day, in: paper.id, undoManager: undoManager) },
            add: { addMilestone($0, from: .timeline) },
            select: { id in
                selection = id
                $timelineFocused.takeKeys()
            },
            open: { open($0) },
            toggleDone: { milestone in
                withAnimation(reduceMotion ? nil : .glide) {
                    store.setDone(!milestone.isDone, ofMilestone: milestone.id, in: paper.id, undoManager: undoManager)
                }
            },
            delete: delete, pan: pan)
    }

    /// A new milestone opens its editor at once, to be named.
    private func addMilestone(_ milestone: Milestone, from anchor: EditorRequest.Anchor) {
        store.addMilestone(milestone, to: paper.id, undoManager: undoManager)
        selection = milestone.id
        if anchor == .timeline {
            open(milestone)
        } else {
            editor = EditorRequest(id: milestone.id, anchor: .list)
        }
    }

    private func open(_ milestone: Milestone) {
        selection = milestone.id
        let isOnAxis = store.plannerAxis.contains(milestone.date())
        deadlineRequest = nil
        editor = EditorRequest(id: milestone.id, anchor: isOnAxis ? .timeline : .list)
    }

    private func delete(_ milestone: Milestone) {
        if selection == milestone.id { selection = nil }
        if editor?.id == milestone.id { editor = nil }
        withAnimation(reduceMotion ? nil : .settle) {
            store.deleteMilestone(milestone.id, undoManager: undoManager)
        }
    }

    /// A block drawn, copied or added as another round, which is then the one selected.
    private func add(_ block: TimeBlock) {
        store.addBlock(block, to: paper.id, undoManager: undoManager)
        selection = block.id
        $timelineFocused.takeKeys()
    }

    /// The editor of a block double-clicked elsewhere, once its page is here.
    private func openRequestedBlock() {
        guard let id = store.blockRequest, let block = paper.blocks.first(where: { $0.id == id }) else { return }
        store.blockRequest = nil
        $timelineFocused.takeKeys()
        open(block)
    }

    /// The editor points at the block's bar, or at its row when the bar is out of sight.
    private func open(_ block: TimeBlock) {
        let axis = store.plannerAxis
        let isOnAxis = block.end.endDate() > axis.start && block.start.startDate() < axis.end
        selection = block.id
        deadlineRequest = nil
        editor = EditorRequest(id: block.id, anchor: isOnAxis ? .timeline : .list)
    }

    private func delete(_ block: TimeBlock) {
        if selection == block.id { selection = nil }
        if editor?.id == block.id { editor = nil }
        withAnimation(reduceMotion ? nil : .settle) {
            store.deleteBlock(block.id, undoManager: undoManager)
        }
    }

    // MARK: Editing deadlines

    /// The flags of the deadlines: those of its own drag to other days, a click selects one, a
    /// double-click opens it, or shows a conference date's details, and a double-click on an empty
    /// day adds one. From the list, everything opens at the rows.
    private func deadlineEditing(_ overview: PaperOverview, at anchor: EditorRequest.Anchor? = nil) -> DeadlineEditing {
        let deadlines = overview.deadlines
        var guides: Set<Day> = [Day(store.now)]
        for block in paper.blocks {
            guides.formUnion([block.start, block.end])
        }
        guides.formUnion(paper.milestones.map(\.day))
        guides.formUnion(deadlines.days())
        return DeadlineEditing(
            selection: selection, guides: guides,
            canMakeMain: { id in deadlines.canChooseMain && deadlines.main?.ownID != id },
            select: { id in
                selection = id
                $timelineFocused.takeKeys()
            },
            open: { open($0, at: anchor) },
            add: { addDeadline(on: $0, at: anchor) },
            move: { id, days in store.moveDeadline(id, byDays: days, in: paper.id, undoManager: undoManager) },
            toggleDone: { deadline in
                withAnimation(reduceMotion ? nil : .glide) {
                    store.setDone(!deadline.isDone, of: deadline, in: paper.id, undoManager: undoManager)
                }
            },
            makeMain: { store.makeMainDeadline($0, of: paper.id, undoManager: undoManager) },
            delete: deleteDeadline,
            wouldConflict: wouldConflict, pan: pan)
    }

    /// The editor of a deadline of its own, or the details of a conference's: at its flag while
    /// that is in sight, else at its row.
    private func open(_ deadline: PaperDeadline, at anchor: EditorRequest.Anchor? = nil) {
        if let id = deadline.ownID {
            selection = id
        }
        let isOnAxis = deadline.date.map(store.plannerAxis.contains) ?? false
        editor = nil
        deadlineRequest = DeadlineRequest(id: deadline.id, anchor: anchor ?? (isOnAxis ? .timeline : .list))
    }

    /// A new deadline of its own, selected, its editor open to name it.
    private func addDeadline(on day: Day?, at anchor: EditorRequest.Anchor?) {
        guard let id = store.addDeadline(to: paper.id, on: day, undoManager: undoManager),
            let deadline = store.overview(for: paper).deadlines.all.first(where: { $0.ownID == id })
        else { return }
        open(deadline, at: anchor)
    }

    private func deleteDeadline(_ id: UUID) {
        if selection == id { selection = nil }
        if deadlineRequest?.id == id.uuidString { deadlineRequest = nil }
        withAnimation(reduceMotion ? nil : .settle) {
            store.deleteDeadline(id, undoManager: undoManager)
        }
    }

    private func wouldConflict(_ id: UUID, days: Int) -> Bool {
        paper.wouldRunPast(movingDeadline: id, byDays: days, catalog: store.catalog, now: store.now)
    }

    private var selectedDeadline: PaperDeadline? {
        guard let selection, paper.deadlines.contains(where: { $0.id == selection }) else { return nil }
        return store.overview(for: paper).deadlines.all.first { $0.ownID == selection }
    }

    /// The editor of a deadline of its own, or a conference date's details, at its flag.
    private func deadlinePopover(_ bounds: [String: Anchor<CGRect>], overview: PaperOverview) -> some View {
        GeometryReader { geo in
            let request = deadlineRequest?.anchor == .timeline ? deadlineRequest : nil
            let drawn = request.flatMap { bounds[$0.id] }.map { geo[$0] }
            let rect = drawn ?? deadlineAnchor
            Color.clear
                .allowsHitTesting(false)
                .frame(width: rect.width, height: rect.height)
                .popover(isPresented: isDeadlineOnTimeline, arrowEdge: .bottom) {
                    if let deadline = overview.deadlines.all.first(where: { $0.id == request?.id }) {
                        DeadlineDetails(
                            paperID: paper.id, deadline: deadline, conference: overview.deadlines.conference?.source
                        ) {
                            deadlineRequest = nil
                            if selection == deadline.ownID { selection = nil }
                        }
                        .environment(store)
                    }
                }
                .position(x: rect.midX, y: rect.midY)
                .onChange(of: drawn, initial: true) { _, drawn in
                    if let drawn { deadlineAnchor = drawn }
                }
        }
    }

    private var isDeadlineOnTimeline: Binding<Bool> {
        Binding(
            get: { deadlineRequest?.anchor == .timeline },
            set: { if !$0, deadlineRequest?.anchor == .timeline { deadlineRequest = nil } })
    }

    /// With a block, milestone or deadline of its own selected: Delete moves it, and only it, to
    /// Recently Deleted, Return opens it, Esc lets it go, and the arrow keys slide it by a day, or by
    /// a week with Shift.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard selection != nil, !press.modifiers.contains(.command) else { return .ignored }
        let days = (press.modifiers.contains(.shift) ? 7 : 1) * (press.key == .leftArrow ? -1 : 1)
        let slide = reduceMotion ? nil : Animation.glide
        if let block = selectedBlock {
            switch press.key {
            case .delete, .deleteForward: delete(block)
            case .return: open(block)
            case .escape: selection = nil
            case .leftArrow, .rightArrow:
                withAnimation(slide) {
                    store.drag(block.dragged(.body, by: days), .body, in: paper.id, undoManager: undoManager)
                }
            default: return .ignored
            }
        } else if let milestone = selectedMilestone {
            switch press.key {
            case .delete, .deleteForward: delete(milestone)
            case .return: open(milestone)
            case .escape: selection = nil
            case .leftArrow, .rightArrow:
                withAnimation(slide) {
                    store.moveMilestone(
                        milestone.id, to: milestone.day.adding(days), in: paper.id, undoManager: undoManager)
                }
            default: return .ignored
            }
        } else if let deadline = selectedDeadline, let id = deadline.ownID {
            switch press.key {
            case .delete, .deleteForward: deleteDeadline(id)
            case .return: open(deadline)
            case .escape: selection = nil
            case .leftArrow, .rightArrow:
                withAnimation(slide) { store.moveDeadline(id, byDays: days, in: paper.id, undoManager: undoManager) }
            default: return .ignored
            }
        } else {
            return .ignored
        }
        return .handled
    }

    /// The editor of a block or milestone opened on the timeline, pointing at it.
    private func timelineEditor(_ bounds: [UUID: Anchor<CGRect>]) -> some View {
        GeometryReader { geo in
            let id = editor?.anchor == .timeline ? editor?.id : nil
            let drawn = id.flatMap { bounds[$0] }.map { geo[$0] }
            let rect = drawn ?? editorAnchor
            Color.clear
                .allowsHitTesting(false)
                .frame(width: rect.width, height: rect.height)
                .popover(isPresented: isEditingOnTimeline, arrowEdge: .bottom) {
                    if let block = paper.blocks.first(where: { $0.id == id }) {
                        BlockEditor(
                            block: Binding($paper.blocks, id: block.id, fallback: block),
                            isDone: Binding(
                                get: { paper.blocks.first { $0.id == block.id }?.isDone ?? false },
                                set: { isDone in
                                    withAnimation(reduceMotion ? nil : .glide) {
                                        store.setDone(isDone, ofBlock: block.id, in: paper.id, undoManager: undoManager)
                                    }
                                }),
                            delete: { delete(block) })
                    } else if let milestone = paper.milestones.first(where: { $0.id == id }) {
                        MilestoneEditor(
                            milestone: Binding($paper.milestones, id: milestone.id, fallback: milestone),
                            isDone: Binding(
                                get: { paper.milestones.first { $0.id == milestone.id }?.isDone ?? false },
                                set: { isDone in
                                    withAnimation(reduceMotion ? nil : .glide) {
                                        store.setDone(
                                            isDone, ofMilestone: milestone.id, in: paper.id, undoManager: undoManager)
                                    }
                                }),
                            delete: { delete(milestone) })
                    }
                }
                .position(x: rect.midX, y: rect.midY)
                .onChange(of: drawn, initial: true) { _, drawn in
                    if let drawn { editorAnchor = drawn }
                }
        }
    }

    private var isEditingOnTimeline: Binding<Bool> {
        Binding(
            get: { editor?.anchor == .timeline },
            set: { if !$0, editor?.anchor == .timeline { editor = nil } })
    }
}
