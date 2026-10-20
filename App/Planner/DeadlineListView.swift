import DrBarKit
import DrBarUI
import SwiftUI

/// A deadline whose editor, or whose conference's details, are open: at its flag on the timeline
/// or at its row in the list.
struct DeadlineRequest: Equatable {
    /// Its `PaperDeadline.id`.
    let id: String
    let anchor: EditorRequest.Anchor
}

/// A paper's or an item's deadlines in the order they come, its conference's and its own: click
/// one of its own to edit it and one of the conference's to see its details, tick the circle once
/// it is done. The deadline selected on the timeline is marked, and Delete deletes one of its own
/// selected here.
struct DeadlineListView: View {
    let deadlines: PaperDeadlines
    let paperID: UUID
    /// What the menus do, as on the timeline, but editing at the row.
    let editing: DeadlineEditing
    @Binding var request: DeadlineRequest?
    @Binding var selection: UUID?

    @Environment(AppStore.self) private var store
    @State private var hovered: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(deadlines.all.enumerated()), id: \.element.id) { index, deadline in
                VStack(spacing: 0) {
                    PaperDeadlineRow(
                        deadline: deadline, isFlag: deadline.id == deadlines.flag?.id,
                        isMain: deadline.id == deadlines.main?.id, now: store.now, isHovered: hovered == deadline.id,
                        isSelected: deadline.ownID != nil && deadline.ownID == selection, editing: editing)
                    if index < deadlines.all.count - 1 {
                        Divider()
                            .padding(.leading, 30)
                    }
                }
                .id(deadline.id)
                .onHover { inside in
                    if inside {
                        hovered = deadline.id
                    } else if hovered == deadline.id {
                        hovered = nil
                    }
                }
                .onTapGesture {
                    $isFocused.takeKeys()
                    editing.open(deadline)
                }
                .contextMenu { DeadlineMenu([deadline], editing: editing) }
                .popover(isPresented: isOpen(deadline.id), arrowEdge: .trailing) {
                    DeadlineDetails(paperID: paperID, deadline: deadline, conference: deadlines.conference?.source) {
                        request = nil
                        if selection == deadline.ownID { selection = nil }
                    }
                    .environment(store)
                }
            }
        }
        .modifier(SelectionKeys(isFocused: $isFocused, delete: deleteSelection, deselect: deselect))
    }

    /// Only a deadline of its own can be selected, and deleted.
    private func deleteSelection() -> Bool {
        guard let id = selection, deadlines.all.contains(where: { $0.ownID == id }) else { return false }
        editing.delete(id)
        return true
    }

    private func deselect() -> Bool {
        guard let id = selection, deadlines.all.contains(where: { $0.ownID == id }) else { return false }
        selection = nil
        return true
    }

    private func isOpen(_ id: String) -> Binding<Bool> {
        let open = DeadlineRequest(id: id, anchor: .list)
        return Binding(get: { request == open }, set: { if !$0, request == open { request = nil } })
    }
}

/// What opens for a deadline: the editor of one of its own, or the details of a conference's.
struct DeadlineDetails: View {
    let paperID: UUID
    let deadline: PaperDeadline
    /// The round that the conference's dates are of.
    let conference: DeadlineRow.Source?
    /// Closes the popover once a deadline of its own is deleted.
    let close: () -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        if let id = deadline.ownID {
            DeadlineEditor(paperID: paperID, id: id, close: close)
        } else if let conference, let (series, edition) = store.catalog.edition(id: conference.edition) {
            let round = edition.rounds.first { $0.id == conference.round }
            ConferenceDetails(series: series, edition: edition, round: round)
                .padding(Theme.Space.l)
                .frame(width: 400)
        }
    }
}

/// Flag · name · date and time · done. The flag is red for the deadline marked on the timeline,
/// and faint, with its name, once the deadline is done or has passed.
private struct PaperDeadlineRow: View {
    let deadline: PaperDeadline
    let isFlag: Bool
    let isMain: Bool
    let now: Date
    let isHovered: Bool
    let isSelected: Bool
    let editing: DeadlineEditing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isClosed: Bool {
        deadline.isClosed(now: now)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    isFlag
                        ? AnyShapeStyle(Color.red.opacity(isClosed ? Theme.pastOpacity : 1))
                        : isClosed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
                )
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(deadline.name)
                .foregroundStyle(isClosed ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.m)
            date
            circle
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.fill.quaternary))
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityActions {
            Button(deadline.ownID == nil ? "Show Details" : "Edit") { editing.open(deadline) }
            if deadline.completion != .decision, !deadline.isDoneByStage {
                Button {
                    editing.toggleDone(deadline)
                } label: {
                    help
                }
            }
            if let id = deadline.ownID {
                if editing.canMakeMain(id) {
                    Button("Make Main Deadline") { editing.makeMain(id) }
                }
                Button("Delete") { editing.delete(id) }
            }
        }
    }

    /// In local time, with the time in its own zone on hover; or why there is no date.
    @ViewBuilder
    private var date: some View {
        if let date = deadline.date {
            Text(DeadlineText.localDateTime(date))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help(DeadlineText.ownTime(date, deadline.timeZone) ?? "")
        } else if deadline.value.isAnnounced {
            HStack(spacing: Theme.Space.s) {
                Text(verbatim: deadline.value.raw)
                    .foregroundStyle(.secondary)
                Text(unreadable)
                    .foregroundStyle(.orange)
            }
            .font(.callout)
        } else {
            Text(SharedText.notAnnounced)
                .foregroundStyle(.secondary)
        }
    }

    /// Why a date that ccfddl gives cannot be read: its time zone, or the date itself.
    private var unreadable: String {
        DeadlineTimeZone.ccf(deadline.timeZone) == nil ? SharedText.unrecognizedTimeZone : SharedText.unreadable
    }

    /// Ticks it off: a paper's main deadline by marking the paper submitted. The notification has
    /// none, as nothing is done by it, but keeps the room so that the dates line up.
    @ViewBuilder
    private var circle: some View {
        let symbol = Image(systemName: deadline.isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 17))
        switch deadline.completion {
        case .tick, .submission:
            Button {
                withAnimation(reduceMotion ? nil : .glide) { editing.toggleDone(deadline) }
            } label: {
                symbol
                    .foregroundStyle(deadline.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .symbolEffect(.bounce, value: reduceMotion ? false : deadline.isDone)
            }
            .buttonStyle(.borderless)
            .disabled(deadline.isDoneByStage)
            .help(help)
            .accessibilityLabel(deadline.isDone ? Text("Done") : Text("Not done"))
        case .decision:
            symbol
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private var help: Text {
        switch (deadline.completion, deadline.isDone) {
        case (.submission, true): Text("Mark as not submitted")
        case (.submission, false): Text("Mark as submitted")
        case (_, true): Text("Mark as not done")
        case (_, false): Text("Mark as done")
        }
    }

    /// "Paper submission, Tuesday, November 17, 12:59, 34 days left, main deadline"
    private var spokenLabel: String {
        var parts = [deadline.name]
        if let date = deadline.date {
            parts.append(date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
            if deadline.isDone {
                parts.append(String(localized: "done", comment: "VoiceOver: a deadline that is done"))
            } else {
                parts.append(date <= now ? SharedText.passed : CountdownText.spoken(date.timeIntervalSince(now)))
            }
        } else {
            parts += deadline.value.isAnnounced ? [deadline.value.raw, unreadable] : [SharedText.notAnnounced]
        }
        if isMain {
            parts.append(String(localized: "main deadline", comment: "VoiceOver: the deadline the plan aims at"))
        }
        return parts.joined(separator: ", ")
    }
}
