import DrBarKit
import DrBarUI
import SwiftUI

/// The fields of a paper's or an item's own deadline: entered in the organizers' time zone, shown
/// in local time as well.
struct CustomDeadlineForm: View {
    @Binding var deadline: CustomDeadline
    /// What the name field suggests.
    var prompt = Text("e.g. Camera-ready")
    /// Whether it is ticked off; `nil` for a paper's main deadline, which is done by submitting.
    var isDone: Binding<Bool>?
    /// Done by the paper's stage, so it cannot be ticked back on its own.
    var isDoneByStage = false
    var makeMain: (() -> Void)?
    var delete: (() -> Void)?

    @FocusState private var nameFocused: Bool

    var body: some View {
        let zone = DeadlineTimeZone.custom(deadline.timeZone) ?? .current
        Form {
            Section {
                TextField("Name", text: $deadline.title, prompt: prompt)
                    .focused($nameFocused)
                Picker("Time zone", selection: timeZone) {
                    Text(
                        "Local time (\(TimeZone.current.localizedName(for: .shortGeneric, locale: .current) ?? TimeZone.current.identifier))"
                    )
                    .tag(TimeZone.current.identifier)
                    // A zone that is in neither list, e.g. local time from another trip.
                    if deadline.timeZone != TimeZone.current.identifier,
                        !DeadlineTimeZone.customChoices.contains(deadline.timeZone)
                    {
                        Text(verbatim: DeadlineText.displayTimeZone(deadline.timeZone)).tag(deadline.timeZone)
                    }
                    Divider()
                    ForEach(DeadlineTimeZone.customChoices, id: \.self) { choice in
                        zoneName(choice).tag(choice)
                    }
                }
                DatePicker("Deadline", selection: $deadline.date)
                    .environment(\.timeZone, zone)
                LabeledContent("In your time zone") {
                    Text(DeadlineText.localDateTime(deadline.date))
                }
            }

            Section {
                LinkField("Link", text: $deadline.link, prompt: "https://")
                TextField("Note", text: $deadline.note, axis: .vertical)
                    .lineLimit(2...6)
            }

            if isDone != nil || makeMain != nil || delete != nil {
                Section {
                    if let isDone {
                        Toggle("Done", isOn: isDone)
                            .disabled(isDoneByStage)
                    }
                    if makeMain != nil || delete != nil {
                        HStack {
                            if let makeMain {
                                Button("Make Main Deadline", action: makeMain)
                            }
                            Spacer()
                            if let delete {
                                Button("Delete Deadline", role: .destructive, action: delete)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .task {
            if deadline.title.isEmpty {
                nameFocused = true
            }
        }
    }

    private func zoneName(_ choice: String) -> Text {
        switch choice {
        case "AoE": Text("AoE (Anywhere on Earth)")
        case "PT": Text("PT (Pacific Time)")
        default: Text(verbatim: choice)
        }
    }

    /// Changing the time zone keeps the wall-clock time: "23:59" stays 23:59 in the new zone.
    private var timeZone: Binding<String> {
        Binding(
            get: { deadline.timeZone },
            set: { newValue in
                let calendar = Calendar.gregorian(in: DeadlineTimeZone.custom(deadline.timeZone) ?? .current)
                let parts = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: deadline.date)
                let target = Calendar.gregorian(in: DeadlineTimeZone.custom(newValue) ?? .current)
                if let moved = target.date(from: parts) {
                    deadline.date = moved
                }
                deadline.timeZone = newValue
            })
    }
}
