import DrBarKit
import DrBarUI
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// The tabs of the Settings window, which other windows can open it on.
enum SettingsTab: String {
    case general, reminders, email, data, about

    static let storageKey = "settingsTab"
}

struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            NotificationSettings()
                .tabItem { Label("Reminders", systemImage: "bell") }
                .tag(SettingsTab.reminders)
            EmailSettings()
                .tabItem { Label("Email", systemImage: "paperplane") }
                .tag(SettingsTab.email)
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag(SettingsTab.data)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Appearance", selection: $store.userData.settings.appearance) {
                    Text("System").tag(AppSettings.Appearance.system)
                    Text("Light").tag(AppSettings.Appearance.light)
                    Text("Dark").tag(AppSettings.Appearance.dark)
                }
                // Open timelines glide to the new range.
                Picker(
                    "Time axis",
                    selection: Binding(
                        get: { store.axisRange },
                        set: { range in withAnimation(reduceMotion ? nil : .glide) { store.axisRange = range } })
                ) {
                    ForEach(AxisRange.allCases, id: \.self) { range in
                        Text(RangePicker.longLabel(range)).tag(range)
                    }
                }
                LabeledContent("Label the axis with") {
                    HStack(spacing: Theme.Space.m) {
                        Toggle("Dates", isOn: $store.userData.settings.axisLabels.shows(dates: true))
                            .disabled(store.userData.settings.axisLabels == .dates)
                        Toggle("Days from Today", isOn: $store.userData.settings.axisLabels.shows(dates: false))
                            .disabled(store.userData.settings.axisLabels == .days)
                    }
                    .toggleStyle(.checkbox)
                }
                Picker("Row size", selection: store.rowSize) {
                    RowSizeChoices()
                }
            }

            Section {
                Picker("Menu bar", selection: $store.userData.settings.menuBarStyle) {
                    ForEach(AppSettings.MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                Picker("Menu bar shows", selection: $store.userData.settings.menuBarSubject) {
                    Text("Next deadline").tag(AppSettings.MenuBarSubject?.none)
                    ForEach(store.userData.groupOrder, id: \.self) { groupID in
                        subjects(Text(verbatim: store.groupName(groupID)), store.userData.items(in: groupID))
                    }
                    if !starredSeries.isEmpty {
                        Section("Conferences") {
                            ForEach(starredSeries) { series in
                                Text(verbatim: series.title).tag(Optional(AppSettings.MenuBarSubject.series(series.id)))
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if LoginItem.needsApproval {
                    HStack {
                        Text("Waiting for your approval in System Settings.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var starredSeries: [ConferenceSeries] {
        store.catalog.series
            .filter { store.isStarred($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The papers, or a group's items, that the menu bar can show, under the group's name.
    @ViewBuilder
    private func subjects(_ title: Text, _ items: [Paper]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Text(item.displayTitle).tag(Optional(AppSettings.MenuBarSubject.paper(item.id)))
                }
            } header: {
                title
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        // The system has the final word, e.g. when approval is still pending.
        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
    }
}

struct NotificationSettings: View {
    @Environment(AppStore.self) private var store
    @State private var authorization: UNAuthorizationStatus?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle(
                    "Remind me about deadlines",
                    isOn: Binding(
                        get: { store.settings.notificationsEnabled },
                        set: { enabled in
                            Task {
                                await store.setNotificationsEnabled(enabled)
                                authorization = await store.notifier.authorizationStatus()
                            }
                        }))
                if authorization == .denied {
                    HStack {
                        Label("Notifications are off for DrBar.", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings") { NSWorkspace.shared.open(SystemSettingsLink.notifications) }
                    }
                }
            }

            Section("Remind me before a deadline") {
                ForEach(AppSettings.reminderDayChoices, id: \.self) { days in
                    Toggle(
                        days == 1 ? String(localized: "1 day before") : String(localized: "\(days) days before"),
                        isOn: Binding(
                            get: { store.settings.reminderDays.contains(days) },
                            set: { isOn in
                                var chosen = Set(store.userData.settings.reminderDays)
                                if isOn { chosen.insert(days) } else { chosen.remove(days) }
                                store.userData.settings.reminderDays = chosen.sorted(by: >)
                            }))
                }
            }
            .disabled(!store.settings.notificationsEnabled)

            Section {
                Toggle(
                    "Remind me at 9:00 when an unfinished block or milestone is due",
                    isOn: $store.userData.settings.blockReminders)
                Toggle("Tell me when ccfddl changes a followed date", isOn: $store.userData.settings.dateChangeAlerts)
            }
            .disabled(!store.settings.notificationsEnabled)
        }
        .formStyle(.grouped)
        .task { authorization = await store.notifier.authorizationStatus() }
    }
}

struct DataSettings: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?
    @State private var confirmingRemoval = false
    @State private var removalError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Conference data") {
                    VStack(alignment: .trailing, spacing: 2) {
                        SyncStatusText()
                        if let attempt = store.syncState.lastAttempt {
                            Text("Last attempt \(attempt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Sync Now") { Task { await store.sync() } }
                        .disabled(store.syncActivity == .syncing)
                }
            }

            Section {
                HStack {
                    Button("Show Data Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.files.userData])
                    }
                    Spacer()
                    Button("Export…", action: export)
                    Button("Import…", action: importData)
                }
                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Your data")
            }

            Section {
                HStack {
                    Text("Remove everything DrBar has stored on this Mac.")
                    Spacer()
                    Button("Remove All Data…", role: .destructive) { confirmingRemoval = true }
                }
                if let removalError {
                    Text(removalError)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Uninstall")
            }
        }
        .formStyle(.grouped)
        .alert("Remove all DrBar data?", isPresented: $confirmingRemoval) {
            Button("Remove and Quit", role: .destructive, action: removeAllData)
            Button("Export First…") { export() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Your papers, groups, plans, deadlines, stars and settings are deleted from this Mac, and DrBar quits. Then move DrBar to the Trash."
            )
        }
    }

    private func export() {
        store.saveNow()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DrBar \(Day(Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UserDataStore.encode(store.userData).write(to: url, options: .atomic)
            message = String(localized: "Exported.")
        } catch {
            message = error.localizedDescription
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = try? UserDataStore.decodeExported(Data(contentsOf: url)) else {
            message = String(localized: "This file is not DrBar data.")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Replace your current data?")
        let papers = imported.data.papers.filter(\.isPaper).count
        alert.informativeText = String(
            localized:
                "Papers: \(papers). Other items: \(imported.data.papers.count - papers). They replace what DrBar has now; a copy of the current file is kept in the data folder."
        )
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.replaceUserData(with: imported.data)
            message =
                imported.issues.isEmpty
                ? String(localized: "Imported.")
                : String(localized: "Imported. Some entries could not be read and were left out.")
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeAllData() {
        do {
            try store.removeAllDataAndQuit()
        } catch {
            removalError = error.localizedDescription
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(verbatim: "DrBar")
                    .font(.title2.weight(.semibold))
                Text("Version \(AppInfo.version)")
                    .foregroundStyle(.secondary)
                Text("Conference deadlines and paper plans on one timeline.")
                HStack(spacing: Theme.Space.l) {
                    Link("Source Code", destination: AppInfo.repositoryURL)
                    Link("Report an Issue", destination: AppInfo.repositoryURL.appending(path: "issues"))
                }
                Divider()
                Text("Conference data comes from ccfddl, maintained by its community under the MIT License.")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("ccfddl on GitHub", destination: AppInfo.ccfddlURL)
                if let notices = Self.acknowledgements {
                    GroupBox("Third-party notices") {
                        Text(verbatim: notices)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 440)
    }

    static var acknowledgements: String? {
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

/// The row sizes, largest first, as Settings and the View menu offer them.
struct RowSizeChoices: View {
    var body: some View {
        Text("Large").tag(AppSettings.RowSize.large)
        Text("Medium").tag(AppSettings.RowSize.medium)
        Text("Small").tag(AppSettings.RowSize.small)
    }
}

#if DEBUG
#Preview("Settings") {
    DemoPreview { SettingsView() }
}
#endif
