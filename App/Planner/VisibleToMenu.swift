import DrBarKit
import SwiftUI

/// Who of the recipients may hear about a paper or an item in the updates of the others: the
/// people an email can reach, under their groups, each ticked on their own.
struct VisibleToItems: View {
    let paper: Paper

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general

    var body: some View {
        let groups = store.userData.mail.groups.filter { !$0.recipients.isEmpty }
        ForEach(groups) { group in
            Section(group.displayName) {
                ForEach(group.recipients) { person in
                    Toggle(
                        person.displayName,
                        isOn: Binding(
                            get: { paper.visibleTo.contains(person.id) },
                            set: { _ in store.toggleVisibility(to: person.id, of: paper.id, undoManager: undoManager) }
                        ))
                }
            }
        }
        if !groups.isEmpty {
            Divider()
        }
        Button("Edit People…") {
            settingsTab = .email
            openSettings()
            NSApp.activate()
        }
    }
}
