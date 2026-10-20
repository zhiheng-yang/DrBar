import AppKit
import CCFDDLKit
import DrBarKit
import DrBarUI
import Observation
import SwiftUI

/// What the planner window shows: the overview, the conferences, a paper or an item, the Archive,
/// or Recently Deleted.
enum PlannerSelection: Hashable {
    case overview
    case conferences
    case paper(UUID)
    case archive
    case recentlyDeleted
}

enum WindowID {
    static let planner = "planner"
    static let deadline = "deadline"
    static let settings = "settings"
}

/// An update that went out, to the group of `groupName`.
struct SentNote: Equatable {
    var id = UUID()
    var paperID: UUID
    var groupName: String
}

/// What File › New Paper or New Group asks the planner for.
enum NewRequest {
    case paper
    case group
}

enum SyncActivity: Equatable {
    case idle
    case syncing
    /// The last attempt failed, without a connection or because ccfddl's answer was refused.
    case failed(offline: Bool)
}

/// The app's state: data, timers and system events. Views read it directly.
///
/// Downloading and parsing happen in `CCFDDLClient`, an actor; everything here runs on the
/// main actor. The only timer fires once a minute.
@MainActor @Observable
final class AppStore {
    static let shared = AppStore()

    // MARK: Data

    private(set) var catalog = ConferenceCatalog.empty
    /// False until `deadlines.json` (or the bundled snapshot) has been read.
    private(set) var catalogLoaded = false
    var userData: UserData {
        didSet { userDataDidChange(from: oldValue) }
    }
    private(set) var syncState = SyncState()
    private(set) var syncActivity = SyncActivity.idle
    /// The moment the bars are drawn for. Advances once a minute.
    private(set) var now = Date()

    // MARK: State shared by the windows

    var plannerSelection: PlannerSelection? = .overview {
        didSet { remember(oldValue) }
    }
    /// Where the planner was before, for Back, and where Back came from, for Forward.
    private(set) var plannerHistory: (back: [PlannerSelection], forward: [PlannerSelection]) = ([], [])
    @ObservationIgnored private var isRetracing = false
    /// The paper whose Send Progress sheet is open in the planner, over whatever page it shows.
    var sendSheetPaperID: UUID?
    /// While an update goes out, its sheet stays, and no other opens.
    var isSendingProgress = false
    /// The update that just went out, which its paper's page tells of for a moment.
    private(set) var sentNote: SentNote?
    /// The conference deadline shown in the deadline window.
    var detailSource: DeadlineRow.Source?
    /// How the menu bar window's axis is zoomed and moved. Back to today and the chosen range when
    /// the window closes.
    var popoverPosition = AxisPosition()
    /// The same for the planner, shared by the overview and the paper pages, until it closes.
    var plannerPosition = AxisPosition()
    /// A paper or item just created, whose title field should take the focus.
    var focusRequest: UUID?
    /// A new paper or group asked for from the File menu, which the planner makes once it is open,
    /// so that Undo there takes it back.
    var newRequest: NewRequest?
    /// A block double-clicked in the overview or the menu bar window, whose editor its paper's
    /// page opens.
    var blockRequest: UUID?
    /// A paper planned backwards from the overview without enough time, whose page says so.
    var tightPlanRequest: UUID?
    /// Set by Browse Conferences…, for the conferences to put the focus in their search field.
    var conferenceSearchRequested = false
    /// A group just created, whose name the sidebar lets the user type.
    var renamingGroup: UUID?
    /// A group with items, which the planner asks about before deleting.
    var pendingGroupDeletion: UUID?
    /// What is about to be deleted for good from Recently Deleted, once the user has said so.
    var pendingPermanentDeletion: Set<UUID> = []
    /// A message about user data that had to be recovered, shown once.
    var dataNotice: String?
    var saveError: String?

    // MARK: Services

    @ObservationIgnored let files: AppFiles
    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored let mail = ProgressMail()
    @ObservationIgnored private var userStore: UserDataStore
    @ObservationIgnored private let client: CCFDDLClient
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The names Siri was last told about (`refreshShortcutNames`).
    @ObservationIgnored var shortcutNames: [String]?
    @ObservationIgnored private var effectsTask: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var isRemovingData = false
    @ObservationIgnored private var started = false
    /// Captured from the menu bar label, which exists for the app's whole life.
    @ObservationIgnored var openWindowAction: OpenWindowAction? {
        didSet { openPendingDestination() }
    }
    @ObservationIgnored private var pendingDestination: Destination?
    /// Reading the conference dates at launch, from the cache or the bundled snapshot, which
    /// whatever needs them first starts and the rest wait for.
    @ObservationIgnored private lazy var catalogLoad = Task { await loadCatalog() }
    private var regularWindows = Set<String>()

    private init() {
        let (files, folderNotice) = Self.dataFolder()
        self.files = files
        var userStore = UserDataStore(files: files)
        var (data, outcome) = Self.loadUserData(from: &userStore)
        self.userStore = userStore
        let isMoved = data.moveListedDeadlines(intoGroupNamed: Self.listedDeadlinesGroupName)
        userData = data
        isDirty = isMoved
        client = CCFDDLClient(
            files: files, userAgent: AppInfo.userAgent,
            bundledAcceptance: Bundle.main.url(forResource: "allacc", withExtension: "yml"))
        dataNotice = folderNotice ?? Self.notice(for: outcome)
    }

    private static func dataFolder() -> (AppFiles, notice: String?) {
        #if DEBUG
        if DemoData.isEnabled { return (DemoData.files, nil) }
        #endif
        do {
            return (try AppFiles.applicationSupport(), nil)
        } catch {
            // Practically impossible inside the sandbox, but never pretend that edits are kept.
            let temporary = AppFiles(directory: FileManager.default.temporaryDirectory.appending(path: "DrBar"))
            try? FileManager.default.createDirectory(at: temporary.directory, withIntermediateDirectories: true)
            return (
                temporary,
                String(localized: "DrBar cannot open its data folder, so changes will not be kept after quitting.")
            )
        }
    }

    /// The group that the deadline list of earlier builds becomes (`UserData.moveListedDeadlines`).
    private static var listedDeadlinesGroupName: String {
        String(localized: "Deadlines", comment: "Group made of the custom deadlines of earlier versions")
    }

    private static func loadUserData(from store: inout UserDataStore) -> (UserData, UserDataStore.LoadOutcome) {
        #if DEBUG
        if DemoData.isEnabled { return (DemoData.userData(), .loaded) }
        #endif
        return store.load()
    }

    #if DEBUG
    /// Loads the catalog without syncing, for snapshots and previews.
    func prepareForDemo() async {
        await waitForCatalog()
        now = Date()
    }
    #endif

    // MARK: Derived values

    var settings: AppSettings {
        userData.settings
    }

    /// The range of the time axis, shared by the popover and the planner.
    var axisRange: AxisRange {
        get { userData.settings.axisRange }
        set { userData.settings.axisRange = newValue }
    }

    var following: Following {
        Following(userData)
    }

    /// The Conferences of the menu bar window and the overview: the starred series, with those
    /// that passed since `start`, where the axis begins. What papers and items target shows with
    /// them.
    func listedRows(since start: Date) -> [DeadlineRow] {
        DeadlineRows.build(
            catalog: catalog, following: Following(starredSeries: userData.favoriteSeries), now: now,
            recentSince: start)
    }

    /// What the menu bar counts down to and reminders announce, once each: every open deadline
    /// ahead of the papers and items, and those of the starred conferences that no paper speaks for.
    var followedDeadlines: [FollowedDeadline] {
        let starred = DeadlineRows.build(
            catalog: catalog, following: Following(starredSeries: userData.favoriteSeries), now: now)
        return DeadlineRows.followed(papers: userData.papers.map(withDeadlines), starred: starred, now: now)
    }

    /// A paper or an item with its deadlines, named as lists name it.
    private func withDeadlines(_ paper: Paper) -> (paper: Paper, deadlines: PaperDeadlines) {
        (Self.named(paper), PaperDeadlines.resolve(paper, catalog: catalog, now: now))
    }

    /// A paper or an item with the title lists show, "Untitled paper" for one without, as what is
    /// said of it elsewhere, such as in reminders, names it.
    private static func named(_ paper: Paper) -> Paper {
        var named = paper
        named.title = paper.displayTitle
        return named
    }

    /// The next deadline of each paper, item and starred conference, nearest first.
    func upcomingDeadlines(limit: Int) -> [FollowedDeadline] {
        DeadlineRows.upcoming(followedDeadlines, limit: limit)
    }

    /// What the menu bar item shows: the paper or deadline picked for it, or else the next
    /// deadlines of everything followed. Something picked that is gone falls back to the latter.
    func menuBarGlance(limit: Int) -> MenuBarGlance {
        settings.menuBarSubject.flatMap { glance(of: $0, limit: limit) }
            ?? MenuBarGlance(upcoming: upcomingDeadlines(limit: limit))
    }

    private func glance(of subject: AppSettings.MenuBarSubject, limit: Int) -> MenuBarGlance? {
        switch subject {
        case let .paper(id):
            guard let paper = userData.papers.first(where: { $0.id == id }) else { return nil }
            let named = withDeadlines(paper)
            let upcoming = DeadlineRows.followed(papers: [named], starred: [], now: now)
            return MenuBarGlance(
                upcoming: Array(upcoming.prefix(limit)),
                plan: MenuBarGlance.Plan(
                    name: named.paper.title, blocks: paper.blocks, deadline: named.deadlines.flag?.date,
                    status: overview(for: paper).status, symbol: userData.symbol(of: paper)))
        case let .series(key):
            guard catalog.series(withKey: key) != nil else { return nil }
            let rows = DeadlineRows.build(
                catalog: catalog, following: Following(starredSeries: [key]), now: now)
            let followed = DeadlineRows.followed(papers: [], starred: rows, now: now)
            return MenuBarGlance(upcoming: DeadlineRows.upcoming(followed, limit: limit))
        case .customDeadline:
            // Of the deadline list of earlier builds, which became papers and items.
            return nil
        }
    }

    /// For "Show in Menu Bar": on picks `subject`, off goes back to the next deadline.
    func showsInMenuBar(_ subject: AppSettings.MenuBarSubject) -> Binding<Bool> {
        Binding(
            get: { self.settings.menuBarSubject == subject },
            set: { self.userData.settings.menuBarSubject = $0 ? subject : nil })
    }

    /// The size of the timelines' rows, for Settings and the View menu, which open ones take on
    /// smoothly.
    var rowSize: Binding<AppSettings.RowSize> {
        Binding(
            get: { self.settings.rowSize },
            set: { size in withMotion(.settle) { self.userData.settings.rowSize = size } })
    }

    /// The axis around today, for lists that are not swiped.
    var axis: TimeAxis {
        TimeAxis(now: now, range: axisRange)
    }

    /// The menu bar window's axis, as it is zoomed and moved.
    var popoverAxis: TimeAxis {
        popoverPosition.axis(now: now, range: axisRange)
    }

    /// The planner's axis, as it is zoomed and moved.
    var plannerAxis: TimeAxis {
        plannerPosition.axis(now: now, range: axisRange)
    }

    /// Everyone in the recipient groups who has a name or an address, in the order of the groups, for
    /// putting on blocks.
    var everyone: [Person] {
        var seen = Set<UUID>()
        return userData.mail.groups.flatMap(\.people).filter { !$0.displayName.isEmpty && seen.insert($0.id).inserted }
    }

    func overview(for paper: Paper) -> PaperOverview {
        PaperOverview(paper: paper, catalog: catalog, now: now)
    }

    func isStarred(_ seriesKey: String) -> Bool {
        userData.favoriteSeries.contains(seriesKey)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        ProgressMail.removeLeftoverAttachments()
        applyAppearance()
        notifier.onOpen = { [weak self] destination in self?.open(destination) }
        notifier.onMarkDone = { [weak self] work in self?.markDone(work) }
        notifier.activate()
        mail.onMessageID = { [weak self] paperID, groupID, subject, messageID in
            self?.storeMessageID(paperID: paperID, groupID: groupID, subject: subject, messageID: messageID)
        }
        observeSystemEvents()
        askForRemindersIfNeeded()
        purgeRecentlyDeleted()
        startTimer()
        network.start { [weak self] in
            Task { @MainActor in await self?.syncIfDue(reconnected: true) }
        }
        Task {
            await waitForCatalog()
            await syncIfDue()
        }
        refreshShortcutNames()
    }

    /// Waits for the conference dates read at launch, reading them if nothing has yet.
    func waitForCatalog() async {
        await catalogLoad.value
    }

    private func loadCatalog() async {
        let now = Date()
        if let cached = await client.cachedCatalog(now: now) {
            catalog = cached
        } else if let snapshot = Bundle.main.url(forResource: "allconf", withExtension: "yml"),
            let installed = try? await client.installSnapshot(at: snapshot, now: now)
        {
            catalog = installed
        }
        syncState = await client.state()
        catalogLoaded = true
        pinSubmittedRounds()
        applySideEffects()
    }

    /// Downloads ccfddl data now (the "Sync Now" button).
    func sync() async {
        guard syncActivity != .syncing else { return }
        syncActivity = .syncing
        do {
            if case let .updated(newCatalog) = try await client.sync(now: Date()) {
                let renames = catalog.renames(in: newCatalog)
                catalog = newCatalog
                catalogLoaded = true
                follow(renames)
                pinSubmittedRounds()
            }
            syncActivity = .idle
            refreshLastSeen(alert: true)
        } catch {
            syncActivity = .failed(offline: error is URLError)
        }
        syncState = await client.state()
        now = Date()
        scheduleSideEffects()
    }

    /// Syncs when the last success is more than 12 hours old. After a failure, waits 15 minutes
    /// before trying again on its own, unless the connection has just come back.
    func syncIfDue(reconnected: Bool = false) async {
        let now = Date()
        if let success = syncState.lastSuccess, now.timeIntervalSince(success) < 12 * 3600 { return }
        if !reconnected, case .failed = syncActivity, let attempt = syncState.lastAttempt,
            now.timeIntervalSince(attempt) < 15 * 60
        {
            return
        }
        await sync()
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { AppStore.shared.tick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        now = Date()
        purgeRecentlyDeleted()
        Task { await syncIfDue() }
    }

    /// What has been in Recently Deleted for thirty days goes for good.
    private func purgeRecentlyDeleted() {
        var data = userData
        if data.purgeRecentlyDeleted(now: now) {
            userData = data
        }
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        func on(
            _ name: Notification.Name, in center: NotificationCenter = center,
            _ action: @escaping @MainActor (AppStore) -> Void
        ) {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { action(AppStore.shared) }
                })
        }
        // Traveling to a conference: recompute what is shown and when reminders fire.
        on(.NSSystemTimeZoneDidChange) { store in
            NSTimeZone.resetSystemTimeZone()
            store.now = Date()
            store.applySideEffects()
        }
        on(.NSCalendarDayChanged) { store in
            store.now = Date()
            store.applySideEffects()
        }
        // Back from System Settings, perhaps with notifications allowed again.
        on(NSApplication.didBecomeActiveNotification) { store in
            store.applySideEffects()
        }
        on(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { store in
            store.now = Date()
            Task { await store.syncIfDue() }
        }
        on(NSApplication.willTerminateNotification) { store in
            store.saveNow()
        }
    }

    // MARK: Saving and side effects

    private func userDataDidChange(from old: UserData) {
        isDirty = true
        scheduleSave()
        if old.settings.appearance != userData.settings.appearance {
            applyAppearance()
        }
        if Following(old) != Following(userData) {
            refreshLastSeen(alert: false)
        }
        if old.withoutLastSeen != userData.withoutLastSeen {
            scheduleSideEffects()
        }
    }

    /// Saves about half a second after the last edit.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, !isRemovingData else { return }
        do {
            try userStore.save(userData)
            isDirty = false
            saveError = nil
            refreshShortcutNames()
        } catch {
            let message = String(localized: "Your changes could not be saved. \(error.localizedDescription)")
            // Said once, in the planner's alert, after what it has yet to say; the menu bar window
            // keeps a warning while it lasts.
            if saveError == nil { dataNotice = dataNotice.map { "\($0)\n\n\(message)" } ?? message }
            saveError = message
        }
    }

    private func scheduleSideEffects() {
        effectsTask?.cancel()
        effectsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.applySideEffects()
        }
    }

    /// Reschedules reminders. A demo run leaves them alone: it shares the notification center with
    /// the real app.
    private func applySideEffects() {
        guard catalogLoaded else { return }
        #if DEBUG
        if DemoData.isEnabled { return }
        #endif
        let reminders = ReminderPlanner.plan(
            deadlines: followedDeadlines, papers: userData.papers.map(Self.named), settings: settings, now: Date())
        notifier.reschedule(reminders)
    }

    private func applyAppearance() {
        NSApp.appearance =
            switch settings.appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
    }

    /// Records the raw text of followed dates; after a sync, notifies about changed ones.
    private func refreshLastSeen(alert: Bool) {
        guard catalogLoaded else { return }
        let items = catalog.items(following: following)
        guard alert else {
            let seen = ChangeDetector.record(items: items, lastSeen: userData.lastSeen)
            if seen != userData.lastSeen {
                userData.lastSeen = seen
            }
            return
        }
        let result = ChangeDetector.detect(items: items, lastSeen: userData.lastSeen)
        if result.lastSeen != userData.lastSeen {
            userData.lastSeen = result.lastSeen
        }
        if settings.notificationsEnabled, settings.dateChangeAlerts, !result.changes.isEmpty {
            notifier.notify(changes: result.changes)
        }
    }

    // MARK: Windows

    func open(_ destination: Destination) {
        guard openWindowAction != nil else {
            pendingDestination = destination
            return
        }
        switch destination {
        case .planner:
            if plannerSelection == nil { plannerSelection = .overview }
            showWindow(WindowID.planner)
        case .conferences:
            plannerSelection = .conferences
            conferenceSearchRequested = true
            showWindow(WindowID.planner)
        case let .paper(id):
            plannerSelection = .paper(id)
            showWindow(WindowID.planner)
        case let .customDeadline(id):
            // A deadline is edited on its paper or item.
            let owner = (userData.papers + userData.archive).first { $0.deadlines.contains { $0.id == id } }
            plannerSelection = owner.map { .paper($0.id) } ?? .overview
            showWindow(WindowID.planner)
        case let .deadline(source):
            detailSource = source
            showWindow(WindowID.deadline)
        }
    }

    /// Send Progress for a paper: its page in the planner with the sheet, unless an update is going
    /// out, whose page the planner then stays on.
    func requestSend(_ paperID: UUID) {
        guard !isSendingProgress else {
            showWindow(WindowID.planner)
            return
        }
        open(.paper(paperID))
        sendSheetPaperID = paperID
    }

    /// The planner, on a block's paper with the block's editor open.
    func editBlock(_ blockID: UUID, of paperID: UUID) {
        blockRequest = blockID
        open(.paper(paperID))
    }

    /// Notes for a moment that the update of a paper went out to a group.
    func noteSent(_ paperID: UUID, to group: RecipientGroup) {
        let note = SentNote(paperID: paperID, groupName: group.displayName)
        sentNote = note
        Task {
            try? await Task.sleep(for: .seconds(4))
            if sentNote == note { sentNote = nil }
        }
    }

    /// File › New Paper and New Group, made in the planner, whichever window is in front.
    func request(_ new: NewRequest) {
        newRequest = new
        open(.planner)
    }

    private func openPendingDestination() {
        guard let destination = pendingDestination, openWindowAction != nil else { return }
        pendingDestination = nil
        open(destination)
    }

    func showWindow(_ id: String) {
        openWindowAction?(id: id)
        NSApp.activate()
    }

    var isPlannerOpen: Bool {
        regularWindows.contains(WindowID.planner)
    }

    /// While a regular window is open, the app shows in the Dock and in ⌘Tab.
    func windowDidAppear(_ id: String) {
        regularWindows.insert(id)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func windowDidDisappear(_ id: String) {
        regularWindows.remove(id)
        // The planner opens on today and the chosen range again, with nothing to go back to.
        if id == WindowID.planner {
            plannerPosition = AxisPosition()
            plannerHistory = ([], [])
        }
        if regularWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: Back and forward

    var canGoBack: Bool {
        plannerHistory.back.contains(where: exists)
    }

    var canGoForward: Bool {
        plannerHistory.forward.contains(where: exists)
    }

    /// The page shown before this one, passing over papers and items deleted since.
    func goBack() {
        while let previous = plannerHistory.back.popLast() {
            guard exists(previous) else { continue }
            if let current = plannerSelection {
                plannerHistory.forward.append(current)
            }
            retrace(to: previous)
            return
        }
    }

    func goForward() {
        while let next = plannerHistory.forward.popLast() {
            guard exists(next) else { continue }
            if let current = plannerSelection {
                plannerHistory.back.append(current)
            }
            retrace(to: next)
            return
        }
    }

    private func retrace(to selection: PlannerSelection) {
        isRetracing = true
        plannerSelection = selection
        isRetracing = false
    }

    /// A new page clears the way forward, as in a browser.
    private func remember(_ previous: PlannerSelection?) {
        guard !isRetracing, let previous, previous != plannerSelection else { return }
        plannerHistory.back.append(previous)
        plannerHistory.back = Array(plannerHistory.back.suffix(50))
        plannerHistory.forward = []
    }

    private func exists(_ selection: PlannerSelection) -> Bool {
        switch selection {
        case .overview, .conferences, .archive, .recentlyDeleted: true
        case let .paper(id): userData.papers.contains { $0.id == id } || userData.archive.contains { $0.id == id }
        }
    }

    // MARK: Editing

    /// A binding that finds the paper by id, so it stays valid while the list changes.
    /// A paper or an item, also one in the Archive, which is shown but not edited.
    func paperBinding(_ id: UUID) -> Binding<Paper>? {
        if let paper = userData.papers.first(where: { $0.id == id }) {
            return Binding(Bindable(self).userData.papers, id: id, fallback: paper)
        }
        guard let paper = userData.archive.first(where: { $0.id == id }) else { return nil }
        return Binding(Bindable(self).userData.archive, id: id, fallback: paper)
    }

    /// One of a paper's or an item's own deadlines, found by id in the same way.
    func deadlineBinding(_ id: UUID, of paperID: UUID) -> Binding<CustomDeadline>? {
        guard let paper = paperBinding(paperID),
            let deadline = paper.wrappedValue.deadlines.first(where: { $0.id == id })
        else { return nil }
        return Binding(paper.deadlines, id: id, fallback: deadline)
    }

    /// The email thread that a paper's updates to its group continue.
    func keepThread(_ thread: MailThread, paperID: UUID) {
        guard let index = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        userData.papers[index].keep(thread)
    }

    /// The next update of a paper to the group starts a new thread.
    func forgetThread(with groupID: UUID, paperID: UUID) {
        guard let index = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        userData.papers[index].forgetThread(with: groupID)
    }

    private func storeMessageID(paperID: UUID, groupID: UUID, subject: String, messageID: String) {
        guard let index = userData.papers.firstIndex(where: { $0.id == paperID }),
            var thread = userData.papers[index].thread(for: groupID),
            thread.subject == subject, thread.messageID == nil
        else { return }
        thread.messageID = messageID
        userData.papers[index].keep(thread)
    }

    /// Reminders that are on in data from elsewhere, an import or another Mac, though this Mac has
    /// never been asked: asked now, and turned off if refused.
    private func askForRemindersIfNeeded() {
        guard settings.notificationsEnabled else { return }
        Task {
            guard await notifier.authorizationStatus() == .notDetermined else { return }
            if !(await notifier.requestAuthorization()) {
                userData.settings.notificationsEnabled = false
            }
        }
    }

    /// Turning reminders on asks for permission the first time; never at launch.
    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await notifier.requestAuthorization()
            userData.settings.notificationsEnabled = granted
        } else {
            userData.settings.notificationsEnabled = false
        }
    }

    /// Settings › Data › "Remove All Data": deletes everything DrBar stored on this Mac, so that
    /// moving the app to the Trash afterwards leaves nothing behind, then quits. If the data
    /// folder cannot be deleted in full, what is open is written back, nothing else is touched,
    /// and the app keeps running.
    func removeAllDataAndQuit() throws {
        isRemovingData = true
        saveTask?.cancel()
        effectsTask?.cancel()
        do {
            try FileManager.default.removeItem(at: files.directory)
        } catch {
            isRemovingData = false
            isDirty = true
            saveNow()
            throw error
        }
        notifier.removeAll()
        if LoginItem.isRegistered {
            try? LoginItem.setEnabled(false)
        }
        ProgressMail.removeLeftoverAttachments()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        Task {
            await DrBarShortcuts.forgetDonations()
            NSApp.terminate(nil)
        }
    }

    /// Replaces all user data with an imported file. The current data is saved and kept as a copy.
    /// What Undo would take back or redo was done to the data that goes, so it goes with it, and so
    /// do the pages of work the file does not have.
    func replaceUserData(with data: UserData) throws {
        try userStore.save(userData)
        try FileStore.keepCopy(of: files.userData, label: "before-import")
        var data = data
        data.moveListedDeadlines(intoGroupNamed: Self.listedDeadlinesGroupName)
        for window in NSApp.windows {
            window.undoManager?.removeAllActions(withTarget: self)
        }
        let kept = Set((data.papers + data.archive).map(\.id))
        let gone = (userData.papers + userData.archive).map(\.id).filter { !kept.contains($0) }
        userData = data
        leavePages(of: gone)
        pinSubmittedRounds()
        saveNow()
        askForRemindersIfNeeded()
    }

    /// Carries what is kept by the names of series and rounds over to those ccfddl has renamed:
    /// stars, targets, ticks, the dates last seen, so that a date that moved with its round's name
    /// is still announced, and what the deadline window shows.
    private func follow(_ renames: CatalogRenames) {
        guard !renames.isEmpty else { return }
        var data = userData
        if data.follow(renames, in: catalog) {
            userData = data
        }
        if let source = detailSource {
            detailSource = .conference(
                series: renames.series(source.series), edition: source.edition,
                round: renames.round(source.round, ofEdition: source.edition) ?? source.round)
        }
    }

    /// Fixes the round of the papers marked submitted without one, as submitting does, once the
    /// catalog is there to find it in.
    private func pinSubmittedRounds() {
        guard catalogLoaded else { return }
        var data = userData
        if data.pinSubmittedRounds(in: catalog, now: Date()) {
            userData = data
        }
    }

    private static func notice(for outcome: UserDataStore.LoadOutcome) -> String? {
        switch outcome {
        case .fresh, .loaded:
            nil
        case let .repaired(copy):
            copy == nil
                ? String(localized: "Some entries in your data file could not be read and were left out.")
                : String(
                    localized:
                        "Some entries in your data file could not be read and were left out. The original file was kept next to it."
                )
        case let .restoredFromBackup(copy, isPartial):
            switch (isPartial, copy != nil) {
            case (true, true):
                String(
                    localized:
                        "Your data file could not be read, so DrBar used the backup, leaving out the entries it could not read there either. Copies were kept next to the data file."
                )
            case (true, false):
                String(
                    localized:
                        "Your data file could not be read, so DrBar used the backup, leaving out the entries it could not read there either."
                )
            case (false, true):
                String(
                    localized:
                        "Your data file could not be read, so DrBar used the backup. The unreadable file was kept next to it."
                )
            case (false, false):
                String(localized: "Your data file could not be read, so DrBar used the backup.")
            }
        case let .unreadable(copy):
            copy == nil
                ? String(localized: "Your data file and its backup could not be read. DrBar started empty.")
                : String(
                    localized:
                        "Your data file and its backup could not be read. DrBar started empty and kept a copy of what was there."
                )
        }
    }
}

private extension UserData {
    /// Everything except the record of seen dates, which changes after syncs.
    var withoutLastSeen: UserData {
        var copy = self
        copy.lastSeen = [:]
        return copy
    }
}

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/zhiheng-yang/DrBar")!
    static let ccfddlURL = URL(string: "https://github.com/ccfddl/ccf-deadlines")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Identifies the app to ccfddl's server, so its maintainers can see where traffic comes from.
    static var userAgent: String {
        "DrBar/\(version) (+\(repositoryURL.absoluteString))"
    }
}
