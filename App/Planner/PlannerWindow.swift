import DrBarKit
import DrBarUI
import SwiftUI

/// The planner, where all editing happens: a sidebar with the overview, the conferences, the papers
/// and the groups of other work, the Archive and Recently Deleted, and the selected page on the
/// right.
struct PlannerWindow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The sidebar starts with the focus, as in Notes or Mail, so no text field opens selected. It
    /// is given it once, as a default focus would take the keys back from every click on the page.
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        NavigationSplitView {
            PlannerSidebar()
                .focused($sidebarFocused)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            // The page that comes in fades in; the one it replaces goes at once, with its toolbar.
            let page = store.plannerSelection ?? .overview
            ZStack {
                detail
                    .id(page)
                    .transition(.page())
            }
            .animation(.page, value: page)
            .hoverCardHost()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HistoryButtons()
                }
            }
        }
        .background(SideButtonReader(back: store.goBack, forward: store.goForward))
        .frame(minWidth: 760, minHeight: 480)
        // A new day moves everything a day to the left.
        .animation(reduceMotion ? nil : .glide, value: Day(store.now))
        .onAppear { sidebarFocused = true }
        .task(id: store.newRequest) { makeRequestedNew() }
        .confirmationDialog(groupDeletionTitle, isPresented: isConfirmingGroupDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = store.pendingGroupDeletion {
                    withAnimation(reduceMotion ? nil : .settle) { store.deleteGroup(id, undoManager: undoManager) }
                }
            }
        } message: {
            Text("Its items go to Recently Deleted, and the group comes back with them.")
        }
        .confirmationDialog(
            permanentDeletionTitle, isPresented: isConfirmingPermanentDeletion, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = store.pendingPermanentDeletion
                withAnimation(reduceMotion ? nil : .settle) { store.deleteForever(ids) }
            }
        } message: {
            Text("This can’t be undone.")
        }
        .sheet(item: sendSheet) { sheet in
            SendProgressSheet(paperID: sheet.id) { store.noteSent(sheet.id, to: $0) }
                .environment(store)
        }
        .alert(
            "Your Data",
            isPresented: Binding(get: { store.dataNotice != nil }, set: { if !$0 { store.dataNotice = nil } })
        ) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.files.userData]) }
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.dataNotice ?? "")
        }
    }

    /// A paper or a group the File menu asked for, with the planner's Undo.
    private func makeRequestedNew() {
        guard let request = store.newRequest else { return }
        store.newRequest = nil
        withAnimation(reduceMotion ? nil : .settle) {
            switch request {
            case .paper: store.addItem(undoManager: undoManager)
            case .group: store.addGroup(undoManager: undoManager)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.plannerSelection {
        case .overview, nil:
            OverviewView()
        case .conferences:
            ConferenceBrowser()
                .navigationTitle("Conferences")
        case let .paper(id):
            if let paper = store.paperBinding(id) {
                PaperDetailView(paper: paper)
            } else {
                ContentUnavailableView("Not Found", systemImage: "doc.text")
            }
        case .archive:
            ArchiveView()
        case .recentlyDeleted:
            RecentlyDeletedView()
        }
    }

    /// Send Progress, over whichever page is shown, so that turning to another while an update goes
    /// out leaves it be.
    private var sendSheet: Binding<SendSheet?> {
        Binding(get: { store.sendSheetPaperID.map(SendSheet.init) }, set: { store.sendSheetPaperID = $0?.id })
    }

    private struct SendSheet: Identifiable {
        let id: UUID
    }

    private var isConfirmingGroupDeletion: Binding<Bool> {
        Binding(get: { store.pendingGroupDeletion != nil }, set: { if !$0 { store.pendingGroupDeletion = nil } })
    }

    private var groupDeletionTitle: Text {
        let name = store.userData.groups.first { $0.id == store.pendingGroupDeletion }?.displayName ?? ""
        return Text("Delete “\(name)”?")
    }

    private var isConfirmingPermanentDeletion: Binding<Bool> {
        Binding(
            get: { !store.pendingPermanentDeletion.isEmpty }, set: { if !$0 { store.pendingPermanentDeletion = [] } })
    }

    private var permanentDeletionTitle: Text {
        let count = store.pendingPermanentDeletion.count
        return count == 1 ? Text("Delete for good?") : Text("Delete \(count) items for good?")
    }
}

/// ‹ and › at the start of the toolbar, as in System Settings: the page shown before, and back
/// again. Back and Forward in the View menu do the same, with ⌘[ and ⌘], and so do the side
/// buttons of a mouse.
private struct HistoryButtons: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ControlGroup {
            Button {
                store.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .help("Back (⌘[)")
            .disabled(!store.canGoBack)
            Button {
                store.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .help("Forward (⌘])")
            .disabled(!store.canGoForward)
        }
    }
}

/// Reads the side buttons of a mouse in the planner window, as Finder and Safari do.
private struct SideButtonReader: NSViewRepresentable {
    let back: () -> Void
    let forward: () -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView()
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.back = back
        view.forward = forward
    }

    final class ReaderView: NSView {
        var back: (() -> Void)?
        var forward: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                let (button, windowNumber) = (event.buttonNumber, event.windowNumber)
                let isTaken = MainActor.assumeIsolated {
                    guard let self, windowNumber == self.window?.windowNumber else { return false }
                    switch button {
                    case 3: self.back?()
                    case 4: self.forward?()
                    default: return false
                    }
                    return true
                }
                return isTaken ? nil : event
            }
        }
    }
}

/// The overview, then the papers and each group of other work under its heading, every one with +
/// for a new item, then the Archive and Recently Deleted. Dragging moves an item within its group
/// or into another, and a heading moves its group with all it holds. A paper or an item is deleted
/// from its menu or with a swipe, never with the Delete key, which a page keeps for its blocks,
/// milestones and deadlines.
struct PlannerSidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store
        // One column of headings and items rather than sections, so that a heading can be dragged
        // and an item dropped into another group.
        let rows = store.userData.sidebarRows
        let papers = Dictionary(store.userData.papers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        List(selection: $store.plannerSelection) {
            Label("Overview", systemImage: "chart.bar.xaxis")
                .tag(PlannerSelection.overview)
            Label("Conferences", systemImage: "list.star")
                .tag(PlannerSelection.conferences)
            ForEach(rows, id: \.self) { row in
                switch row {
                case let .heading(groupID):
                    GroupHeading(groupID: groupID)
                case let .item(id):
                    if let item = papers[id] {
                        itemRow(item)
                    }
                }
            }
            .onMove { store.arrange(rows.moving(fromOffsets: $0, toOffset: $1), undoManager: undoManager) }
            if !store.userData.archive.isEmpty || store.userData.hasDeletedEntries {
                Section {
                    if !store.userData.archive.isEmpty {
                        Label("Archive", systemImage: "archivebox")
                            .tag(PlannerSelection.archive)
                    }
                    if store.userData.hasDeletedEntries {
                        Label("Recently Deleted", systemImage: "trash")
                            .tag(PlannerSelection.recentlyDeleted)
                            .contextMenu {
                                Button("Delete All…") {
                                    store.pendingPermanentDeletion = Set(store.userData.deletedEntries.map(\.id))
                                }
                            }
                    }
                }
            }
        }
        .symbolRenderingMode(.hierarchical)
        .barsGrowIn()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }

    /// Rows that go, archived or deleted, let the others close up, unless motion is reduced.
    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .settle, change)
    }

    private func itemRow(_ item: Paper) -> some View {
        PaperSidebarRow(paper: item)
            .tag(PlannerSelection.paper(item.id))
            .contextMenu { menu(for: item) }
            // As in Mail: swipe left to delete, right to archive.
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    animated { store.deletePaper(item.id, undoManager: undoManager) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    animated { store.archive(item.id, undoManager: undoManager) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.indigo)
            }
            .accessibilityAction(named: Text("Move Up")) { store.moveItem(item.id, by: -1, undoManager: undoManager) }
            .accessibilityAction(named: Text("Move Down")) { store.moveItem(item.id, by: 1, undoManager: undoManager) }
    }

    @ViewBuilder
    private func menu(for item: Paper) -> some View {
        Toggle("Show in Menu Bar", isOn: store.showsInMenuBar(.paper(item.id)))
        if !store.userData.groups.isEmpty {
            Menu("Move To") {
                ForEach(store.userData.groupOrder, id: \.self) { groupID in
                    Button(store.groupName(groupID)) { store.move(item.id, toGroup: groupID, undoManager: undoManager) }
                        .disabled(item.groupID == groupID)
                }
            }
        }
        Menu("Visible To") {
            VisibleToItems(paper: item)
        }
        Button("Archive") { animated { store.archive(item.id, undoManager: undoManager) } }
        Divider()
        Button(item.isPaper ? "Delete Paper" : "Delete Item", role: .destructive) {
            animated { store.deletePaper(item.id, undoManager: undoManager) }
        }
    }
}

/// A paper or an item in the sidebar, with its plan in a thin bar under the title. The bars of the
/// sidebar share the time axis of the timelines, so whose deadline comes first shows at a glance.
struct PaperSidebarRow: View {
    let paper: Paper
    @Environment(AppStore.self) private var store

    var body: some View {
        let overview = store.overview(for: paper)
        Label {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(paper.displayTitle)
                        .lineLimit(1)
                    if let symbol = overview.status.symbolName {
                        Image(systemName: symbol)
                            .imageScale(.small)
                            .foregroundStyle(overview.status.color)
                            .help(overview.status.localizedDescription)
                    }
                }
                if !paper.blocks.isEmpty || overview.flag?.date != nil {
                    PlanProgressBar(
                        blocks: paper.blocks, deadline: overview.flag?.date, now: store.now, axis: store.axis)
                }
            }
        } icon: {
            Image(systemName: store.userData.symbol(of: paper))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            paper.blocks.isEmpty
                ? Text(verbatim: PaperText.subtitle(overview: overview) ?? "")
                : Text("\(overview.progress.formatted(.percent.precision(.fractionLength(0)))) of the plan done"))
    }
}

/// The foot of the sidebar: a new group, as Notes makes a new folder, and Settings, where it is
/// found in many Mac apps' windows too.
struct SidebarFooter: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .settle) { store.addGroup(undoManager: undoManager) }
            } label: {
                Label("New Group", systemImage: "plus.circle")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("New Group (⇧⌘N)")
            Spacer()
            Button {
                openSettings()
                NSApp.activate()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings (⌘,)")
            .accessibilityLabel(Text("Settings"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// The heading of the papers or of a group, drawn as the sidebar draws its section headers, with +
/// for a new item. A group's name can be typed in place after a double click or Rename Group.
private struct GroupHeading: View {
    let groupID: UUID?
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @FocusState private var isNaming: Bool

    var body: some View {
        let isRenaming = groupID != nil && store.renamingGroup == groupID
        HStack {
            if isRenaming {
                TextField("Name", text: $name, prompt: Text("Untitled Group"))
                    .textFieldStyle(.plain)
                    .focused($isNaming)
                    .onAppear {
                        name = store.groupName(groupID)
                        isNaming = true
                    }
                    .onSubmit(rename)
                    .onChange(of: isNaming) { _, isNaming in
                        if !isNaming { rename() }
                    }
                    .onExitCommand { store.renamingGroup = nil }
            } else {
                Text(store.groupName(groupID))
                    .onTapGesture(count: 2) {
                        if groupID != nil { store.renamingGroup = groupID }
                    }
            }
            Spacer()
            Button(action: add) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(groupID == nil ? Text("New Paper (⌘N)") : Text("New Item"))
            .accessibilityLabel(groupID == nil ? Text("New Paper") : Text("New Item"))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.leading, -2)
        .padding(.top, 10)
        .selectionDisabled()
        .moveDisabled(isRenaming)
        .accessibilityAddTraits(.isHeader)
        .accessibilityAction(named: Text("Move Up")) { store.moveGroup(groupID, by: -1, undoManager: undoManager) }
        .accessibilityAction(named: Text("Move Down")) { store.moveGroup(groupID, by: 1, undoManager: undoManager) }
        .contextMenu {
            if let groupID {
                Button("New Item", action: add)
                Button("Rename Group") { store.renamingGroup = groupID }
                Picker("Icon", selection: symbol(of: groupID)) {
                    ForEach(ItemGroup.symbols, id: \.self) { symbol in
                        Label(GroupSymbolName.of(symbol), systemImage: symbol)
                            .tag(symbol)
                    }
                }
                Divider()
                Button("Delete Group…", role: .destructive) {
                    if store.userData.hasItems(inGroup: groupID) {
                        store.pendingGroupDeletion = groupID
                    } else {
                        withAnimation(reduceMotion ? nil : .settle) {
                            store.deleteGroup(groupID, undoManager: undoManager)
                        }
                    }
                }
            } else {
                Button("New Paper", action: add)
            }
        }
    }

    private func add() {
        withAnimation(reduceMotion ? nil : .settle) { store.addItem(in: groupID, undoManager: undoManager) }
    }

    private func symbol(of groupID: UUID) -> Binding<String> {
        Binding(
            get: { store.userData.groups.first { $0.id == groupID }?.shownSymbol ?? ItemGroup.symbols[0] },
            set: { store.setSymbol($0, ofGroup: groupID, undoManager: undoManager) })
    }

    private func rename() {
        guard let groupID, store.renamingGroup == groupID else { return }
        store.renameGroup(groupID, to: name.trimmingCharacters(in: .whitespaces), undoManager: undoManager)
        store.renamingGroup = nil
    }
}

/// What each symbol a group can have stands for, as the Icon menu names it.
private enum GroupSymbolName {
    static func of(_ symbol: String) -> String {
        switch symbol {
        case "list.bullet.clipboard": String(localized: "Checklist", comment: "Icon of a group")
        case "magnifyingglass": String(localized: "Peer Review", comment: "Icon of a group")
        case "envelope": String(localized: "Mail", comment: "Icon of a group")
        case "briefcase": String(localized: "Work", comment: "Icon of a group")
        case "studentdesk": String(localized: "Study", comment: "Icon of a group")
        case "trophy": String(localized: "Award", comment: "Icon of a group")
        case "banknote": String(localized: "Grant", comment: "Icon of a group")
        case "airplane": String(localized: "Travel", comment: "Icon of a group")
        case "person.2": String(localized: "People", comment: "Icon of a group")
        case "mic": String(localized: "Talk", comment: "Icon of a group")
        case "book": String(localized: "Reading", comment: "Icon of a group")
        default: String(localized: "Calendar", comment: "Icon of a group")
        }
    }
}

#if DEBUG
#Preview("Planner") {
    DemoPreview { PlannerWindow() }
        .frame(width: 1100, height: 640)
        .onAppear { AppStore.shared.plannerSelection = .overview }
}

#Preview("Paper") {
    DemoPreview { PlannerWindow() }
        .frame(width: 1100, height: 900)
        .onAppear { AppStore.shared.plannerSelection = AppStore.shared.userData.papers.first.map { .paper($0.id) } }
}
#endif
