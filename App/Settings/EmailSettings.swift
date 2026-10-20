import DrBarKit
import DrBarUI
import SwiftUI

/// How progress emails are signed and sent, and the groups of people they go to, each with
/// its own thread per paper.
struct EmailSettings: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focus: Field?
    @State private var pendingRemoval: RecipientGroup?

    enum Field: Hashable {
        case groupName(RecipientGroup.ID)
        case person(Person.ID)
    }

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                TextField("Your name", text: $store.userData.mail.signature, prompt: Text("Signs each email"))
                TextField(
                    "Send from", text: $store.userData.mail.senderAddress,
                    prompt: Text("Your address in Mail, e.g. you@example.edu"))
            }
            let groups = store.userData.mail.groups
            ForEach($store.userData.mail.groups) { $group in
                GroupSection(
                    group: $group, focus: $focus,
                    canMoveUp: groups.first?.id != group.id, canMoveDown: groups.last?.id != group.id,
                    move: { move(group.id, by: $0) }, remove: { remove(group) })
            }
            Section {
                HStack {
                    Spacer()
                    Button("Add Group", action: addGroup)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            store.userData.mail.removeBlankPeople()
            store.userData.forgetRemovedPeople()
        }
        .confirmationDialog(
            "Delete “\(pendingRemoval?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { group in
            Button("Delete Group", role: .destructive) { store.userData.removeRecipientGroup(group.id) }
        } message: { _ in
            Text("Its people are removed from DrBar. Emails already sent stay in Mail.")
        }
    }

    /// A new group of the user's own, named right away.
    private func addGroup() {
        let groups = store.userData.mail.groups
        let group = RecipientGroup(kind: .other, language: groups.last?.language ?? .english)
        store.userData.mail.groups.append(group)
        // Once its section is there.
        Task { focus = .groupName(group.id) }
    }

    /// Moves a group one place up or down, which is the order of the To menu.
    private func move(_ id: RecipientGroup.ID, by offset: Int) {
        var groups = store.userData.mail.groups
        guard let index = groups.firstIndex(where: { $0.id == id }), groups.indices.contains(index + offset) else {
            return
        }
        groups.swapAt(index, index + offset)
        withMotion(.settle) {
            store.userData.mail.groups = groups
        }
    }

    /// An empty group goes at once; one with people or threads is asked about first.
    private func remove(_ group: RecipientGroup) {
        let hasThreads = store.userData.hasThreads(with: group.id)
        if group.people.allSatisfy({ $0.displayName.isEmpty }) && !hasThreads {
            store.userData.removeRecipientGroup(group.id)
        } else {
            pendingRemoval = group
        }
    }
}

private struct GroupSection: View {
    @Binding var group: RecipientGroup
    var focus: FocusState<EmailSettings.Field?>.Binding
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        Section {
            if group.kind == .other {
                TextField("Name", text: $group.name, prompt: Text("e.g. Reading group"))
                    .focused(focus, equals: .groupName(group.id))
            }
            ForEach($group.people) { $person in
                PersonRow(person: $person, focus: focus) {
                    group.people.removeAll { $0.id == person.id }
                }
                .contextMenu {
                    Button("Move Up") { movePerson(person.id, by: -1) }
                        .disabled(group.people.first?.id == person.id)
                    Button("Move Down") { movePerson(person.id, by: 1) }
                        .disabled(group.people.last?.id == person.id)
                }
                .accessibilityAction(named: Text("Move Up")) { movePerson(person.id, by: -1) }
                .accessibilityAction(named: Text("Move Down")) { movePerson(person.id, by: 1) }
            }
            HStack {
                Spacer()
                Button("Add Person") {
                    let person = Person()
                    group.people.append(person)
                    // Once its row is there.
                    Task { focus.wrappedValue = .person(person.id) }
                }
            }
            Picker("Email language", selection: $group.language) {
                Text(verbatim: "English").tag(MailLanguage.english)
                Text(verbatim: "中文").tag(MailLanguage.chinese)
            }
            Toggle("Leave buffer blocks out of the image", isOn: $group.hidesBufferBlocks)
        } header: {
            HStack {
                Text(group.displayName)
                Spacer()
                Menu {
                    Button("Move Up") { move(-1) }
                        .disabled(!canMoveUp)
                    Button("Move Down") { move(1) }
                        .disabled(!canMoveDown)
                    Divider()
                    Button("Delete Group…", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("More for \(group.displayName)"))
            }
        }
    }

    /// Moves someone one place up or down, which is their place in the To field.
    private func movePerson(_ id: Person.ID, by offset: Int) {
        guard let index = group.people.firstIndex(where: { $0.id == id }),
            group.people.indices.contains(index + offset)
        else { return }
        withMotion(.settle) {
            group.people.swapAt(index, index + offset)
        }
    }
}

/// A name and an address, with a mark when the address cannot be one.
private struct PersonRow: View {
    @Binding var person: Person
    var focus: FocusState<EmailSettings.Field?>.Binding
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Full name", text: $person.name, prompt: Text("Full name"))
                .focused(focus, equals: .person(person.id))
                .frame(maxWidth: 160)
            TextField("Email address", text: $person.email, prompt: Text(verbatim: "name@example.edu"))
                .textContentType(.emailAddress)
            if !person.address.isEmpty && !person.hasAddress {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Not an email address")
                    .accessibilityLabel(Text("Not an email address"))
            }
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
            .accessibilityLabel(Text("Remove \(person.displayName)"))
        }
        .labelsHidden()
    }
}
