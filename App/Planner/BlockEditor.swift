import DrBarKit
import DrBarUI
import SwiftUI

/// A block or milestone whose editor is open, and whether the popover points at it on the
/// timeline or at its row in the list.
struct EditorRequest: Equatable {
    enum Anchor {
        case timeline, list
    }

    let id: UUID
    let anchor: Anchor
}

/// The popover that edits one block, from its row in the list or its bar in the timeline.
struct BlockEditor: View {
    @Binding var block: TimeBlock
    @Binding var isDone: Bool
    /// Moves the block up or down the list, for the list's own popover.
    var move: ((Int) -> Void)?
    var canMoveUp = false
    var canMoveDown = false
    let delete: () -> Void

    var body: some View {
        Form {
            Picker("Kind", selection: $block.kind) {
                ForEach(TimeBlock.Kind.allCases, id: \.self) { kind in
                    Text(kind.localizedName).tag(kind)
                }
            }
            if block.kind == .custom {
                TextField("Name", text: $block.customName, prompt: Text("Name"))
            }
            DatePicker("Start", selection: startDate, displayedComponents: .date)
            DatePicker("End", selection: endDate, in: block.start.startDate()..., displayedComponents: .date)
            PeoplePicker(people: $block.people)
            Toggle("Done", isOn: $isDone)
            HStack {
                if let move {
                    Button {
                        move(-1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canMoveUp)
                    .help("Move Up")
                    Button {
                        move(1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canMoveDown)
                    .help("Move Down")
                }
                Spacer()
                Button("Delete Block", role: .destructive, action: delete)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
    }

    /// The start may move past the end; the end then follows, as the end can never be earlier.
    private var startDate: Binding<Date> {
        Binding(
            get: { block.start.startDate() },
            set: { date in
                block.start = Day(date)
                if block.end < block.start { block.end = block.start }
            })
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { block.end.startDate() },
            set: { date in block.end = max(Day(date), block.start) })
    }
}

/// Who works on a block besides the user: anyone from the recipient groups in Settings › Email.
private struct PeoplePicker: View {
    @Binding var people: [UUID]
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general

    var body: some View {
        let everyone = store.everyone
        LabeledContent("With") {
            Menu(summary(everyone)) {
                ForEach(everyone) { person in
                    Toggle(
                        person.displayName,
                        isOn: Binding(
                            get: { people.contains(person.id) },
                            set: { isOn in
                                if isOn { people.append(person.id) } else { people.removeAll { $0 == person.id } }
                            }))
                }
                if !everyone.isEmpty {
                    Divider()
                }
                Button("Edit People…") {
                    settingsTab = .email
                    openSettings()
                    NSApp.activate()
                }
            }
            .fixedSize()
        }
    }

    /// "Jane Doe, Sam Lee", or "Only you" for the user's own work.
    private func summary(_ everyone: [Person]) -> String {
        let names = everyone.filter { people.contains($0.id) }.map(\.displayName)
        return names.isEmpty ? String(localized: "Only you") : names.formatted(.list(type: .and))
    }
}

/// The popover that edits one milestone, from its diamond or its row. A new one starts with its
/// name selected, ready to be typed.
struct MilestoneEditor: View {
    @Binding var milestone: Milestone
    @Binding var isDone: Bool
    let delete: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            TextField("Name", text: $milestone.title, prompt: Text("e.g. Internal deadline"))
                .focused($nameFocused)
            DatePicker("Date", selection: day, displayedComponents: .date)
            Toggle("Done", isOn: $isDone)
            HStack {
                Spacer()
                Button("Delete Milestone", role: .destructive, action: delete)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .task {
            if milestone.title.isEmpty {
                nameFocused = true
            }
        }
    }

    private var day: Binding<Date> {
        Binding(get: { milestone.day.startDate() }, set: { milestone.day = Day($0) })
    }
}
