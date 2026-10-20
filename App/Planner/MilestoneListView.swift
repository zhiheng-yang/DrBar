import DrBarKit
import DrBarUI
import SwiftUI

/// A paper's milestones in the order they come: click one to edit it, tick the circle when it is
/// done. The milestone selected on the timeline is marked, and Delete deletes the one selected
/// here.
struct MilestoneListView: View {
    @Binding var milestones: [Milestone]
    /// The paper's blocks, whose colors the milestones take.
    let blocks: [TimeBlock]
    let paperID: UUID
    /// The milestone whose editor is open, here or at its diamond on the timeline.
    @Binding var editor: EditorRequest?
    @Binding var selection: UUID?

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Milestone.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        let ordered = milestones.sorted { $0.day < $1.day }
        let colors = BlockColor.colors(for: milestones, among: blocks)
        VStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, milestone in
                VStack(spacing: 0) {
                    MilestoneRow(
                        milestone: milestone, color: colors[milestone.id] ?? Palette.calm, today: Day(store.now),
                        isHovered: hovered == milestone.id,
                        isSelected: selection == milestone.id, toggleDone: { toggleDone(milestone) },
                        edit: { edit(milestone.id) })
                    if index < ordered.count - 1 {
                        Divider()
                            .padding(.leading, 30)
                    }
                }
                .onHover { inside in
                    if inside {
                        hovered = milestone.id
                    } else if hovered == milestone.id {
                        hovered = nil
                    }
                }
                .onTapGesture { edit(milestone.id) }
                .popover(isPresented: isEditing(milestone.id), arrowEdge: .trailing) {
                    MilestoneEditor(
                        milestone: Binding($milestones, id: milestone.id, fallback: milestone),
                        isDone: Binding(
                            get: { milestones.first { $0.id == milestone.id }?.isDone ?? false },
                            set: { isDone in
                                withAnimation(reduceMotion ? nil : .glide) {
                                    store.setDone(
                                        isDone, ofMilestone: milestone.id, in: paperID, undoManager: undoManager)
                                }
                            }
                        ),
                        delete: { delete(milestone.id) })
                }
            }
        }
        .modifier(SelectionKeys(isFocused: $isFocused, delete: deleteSelection, deselect: deselect))
    }

    private func edit(_ id: Milestone.ID) {
        selection = id
        $isFocused.takeKeys()
        editor = EditorRequest(id: id, anchor: .list)
    }

    private func delete(_ id: Milestone.ID) {
        if selection == id { selection = nil }
        if editor?.id == id { editor = nil }
        withAnimation(reduceMotion ? nil : .settle) {
            store.deleteMilestone(id, undoManager: undoManager)
        }
    }

    private func deleteSelection() -> Bool {
        guard let id = selection, milestones.contains(where: { $0.id == id }) else { return false }
        delete(id)
        return true
    }

    private func deselect() -> Bool {
        guard let id = selection, milestones.contains(where: { $0.id == id }) else { return false }
        selection = nil
        return true
    }

    private func isEditing(_ id: Milestone.ID) -> Binding<Bool> {
        let request = EditorRequest(id: id, anchor: .list)
        return Binding(get: { editor == request }, set: { if !$0, editor == request { editor = nil } })
    }

    private func toggleDone(_ milestone: Milestone) {
        withAnimation(reduceMotion ? nil : .glide) {
            store.setDone(!milestone.isDone, ofMilestone: milestone.id, in: paperID, undoManager: undoManager)
        }
    }
}

/// Diamond · name · day · done, the day in orange once it has passed without being done.
private struct MilestoneRow: View {
    let milestone: Milestone
    let color: Color
    let today: Day
    let isHovered: Bool
    let isSelected: Bool
    let toggleDone: () -> Void
    let edit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            MilestoneDiamond(milestone, color: color, today: today, size: 8)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(milestone.displayName)
                .foregroundStyle(milestone.isDone ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.m)
            Text(MilestoneText.day(milestone.day))
                .foregroundStyle(
                    milestone.isOverdue(today: today) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary)
                )
                .monospacedDigit()
            Button(action: toggleDone) {
                Image(systemName: milestone.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(milestone.isDone ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
                    .symbolEffect(.bounce, value: reduceMotion ? false : milestone.isDone)
            }
            .buttonStyle(.borderless)
            .help(milestone.isDone ? Text("Mark as not done") : Text("Mark as done"))
            .accessibilityLabel(milestone.isDone ? Text("Done") : Text("Not done"))
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
        .accessibilityLabel(Text(MilestoneText.help(milestone)))
        .accessibilityAction(named: Text("Edit"), edit)
    }
}
