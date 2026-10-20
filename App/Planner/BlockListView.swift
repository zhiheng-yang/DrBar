import DrBarKit
import DrBarUI
import SwiftUI

/// A paper's time blocks as a quiet list: click a block to edit it, tick the circle when it is
/// done, drag it to another place in the list. The block selected in the timeline is marked, and
/// Delete deletes the one selected here.
struct BlockListView: View {
    @Binding var blocks: [TimeBlock]
    let paperID: UUID
    /// The block whose editor is open, here or at its bar in the timeline.
    @Binding var editor: EditorRequest?
    @Binding var selection: TimeBlock.ID?

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: TimeBlock.ID?
    @State private var reorder: RowMove?
    /// Set by Esc during a reorder, until the button comes up.
    @State private var isReorderCancelled = false
    @State private var cancellation = DragCancellation()
    /// From the top of one row to the top of the next, divider included.
    @State private var pitch: CGFloat = 40
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                row(block, at: index)
            }
        }
        .modifier(SelectionKeys(isFocused: $isFocused, delete: deleteSelection, deselect: deselect))
    }

    private func row(_ block: TimeBlock, at index: Int) -> some View {
        let isLifted = reorder?.from == index
        return VStack(spacing: 0) {
            BlockRow(
                block: block, isOverdue: !block.isDone && block.end < Day(store.now),
                people: block.people.compactMap { store.userData.people[$0] },
                isHovered: hovered == block.id && reorder == nil, isSelected: selection == block.id,
                isLifted: isLifted, toggleDone: { toggleDone(block) }, edit: { edit(block.id) })
            if index < blocks.count - 1 {
                Divider()
                    .padding(.leading, 30)
                    .opacity(reorder == nil ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            if index == 0, blocks.count > 1 { pitch = height }
        }
        .offset(y: reorder?.offset(ofRowAt: index, rowHeight: pitch, count: blocks.count) ?? 0)
        .zIndex(isLifted ? 1 : 0)
        .animation(
            isLifted || reduceMotion ? nil : .makeRoom,
            value: reorder?.destination(rowHeight: pitch, count: blocks.count)
        )
        .onHover { inside in
            if inside {
                hovered = block.id
            } else if hovered == block.id {
                hovered = nil
            }
        }
        .onTapGesture { edit(block.id) }
        .gesture(reorderGesture(from: index))
        .popover(isPresented: isEditing(block.id), arrowEdge: .trailing) {
            BlockEditor(
                block: Binding($blocks, id: block.id, fallback: block),
                isDone: Binding(
                    get: { blocks.first { $0.id == block.id }?.isDone ?? false },
                    set: { isDone in
                        withAnimation(reduceMotion ? nil : .glide) {
                            store.setDone(isDone, ofBlock: block.id, in: paperID, undoManager: undoManager)
                        }
                    }),
                move: { move(block.id, by: $0) }, canMoveUp: index > 0, canMoveDown: index < blocks.count - 1,
                delete: { delete(block.id) })
        }
    }

    /// Dragging a block row: it follows the pointer, the others make room, and on release it
    /// settles into its new place.
    private func reorderGesture(from index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard !isReorderCancelled else { return }
                cancellation.listen {
                    reorder = nil
                    isReorderCancelled = true
                }
                reorder = RowMove(from: index, translation: value.translation.height)
            }
            .onEnded { value in
                cancellation.stop()
                guard !isReorderCancelled else {
                    isReorderCancelled = false
                    return
                }
                let move = RowMove(from: index, translation: value.translation.height)
                let landing = move.destination(rowHeight: pitch, count: blocks.count)
                let order = move.apply(to: blocks.map(\.id), rowHeight: pitch)
                withAnimation(reduceMotion ? nil : .drop) {
                    reorder?.translation = Double(landing - index) * pitch
                } completion: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        reorder = nil
                        store.setBlockOrder(order, in: paperID, undoManager: undoManager)
                    }
                }
            }
    }

    private func edit(_ id: TimeBlock.ID) {
        selection = id
        $isFocused.takeKeys()
        editor = EditorRequest(id: id, anchor: .list)
    }

    private func delete(_ id: TimeBlock.ID) {
        if selection == id { selection = nil }
        if editor?.id == id { editor = nil }
        withAnimation(reduceMotion ? nil : .settle) {
            store.deleteBlock(id, undoManager: undoManager)
        }
    }

    private func deleteSelection() -> Bool {
        guard let id = selection, blocks.contains(where: { $0.id == id }) else { return false }
        delete(id)
        return true
    }

    private func deselect() -> Bool {
        guard let id = selection, blocks.contains(where: { $0.id == id }) else { return false }
        selection = nil
        return true
    }

    private func isEditing(_ id: TimeBlock.ID) -> Binding<Bool> {
        let request = EditorRequest(id: id, anchor: .list)
        return Binding(get: { editor == request }, set: { if !$0, editor == request { editor = nil } })
    }

    private func toggleDone(_ block: TimeBlock) {
        withAnimation(reduceMotion ? nil : .glide) {
            store.setDone(!block.isDone, ofBlock: block.id, in: paperID, undoManager: undoManager)
        }
    }

    private func move(_ id: TimeBlock.ID, by offset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks.indices.contains(index + offset) else {
            return
        }
        var order = blocks.map(\.id)
        order.swapAt(index, index + offset)
        store.setBlockOrder(order, in: paperID, undoManager: undoManager)
    }
}

/// Color dot · name · who works on it · dates · length · done, the dates in orange once the block has
/// ended without being done.
private struct BlockRow: View {
    let block: TimeBlock
    let isOverdue: Bool
    /// Who works on it besides the user.
    let people: [Person]
    let isHovered: Bool
    let isSelected: Bool
    let isLifted: Bool
    let toggleDone: () -> Void
    let edit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Circle()
                .fill(BlockColor.color(for: block).opacity(block.isDone ? 1 : Theme.undoneOpacity + 0.2))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(block.displayName)
                .foregroundStyle(block.isDone ? .secondary : .primary)
                .lineLimit(1)
            if !people.isEmpty {
                PeopleBadges(people, color: BlockColor.color(for: block), size: 16)
                    .help(people.map(\.displayName).formatted(.list(type: .and)))
            }
            Spacer(minLength: Theme.Space.m)
            Text(BlockText.range(block))
                .foregroundStyle(isOverdue ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .monospacedDigit()
            Text(BlockText.days(block.length))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Button(action: toggleDone) {
                Image(systemName: block.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        block.isDone ? AnyShapeStyle(BlockColor.color(for: block)) : AnyShapeStyle(.tertiary)
                    )
                    .symbolEffect(.bounce, value: reduceMotion ? false : block.isDone)
            }
            .buttonStyle(.borderless)
            .help(block.isDone ? Text("Mark as not done") : Text("Mark as done"))
            .accessibilityLabel(block.isDone ? Text("Done") : Text("Not done"))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
                .shadow(color: .black.opacity(isLifted ? 0.18 : 0), radius: 8, y: 3)
                .opacity(isHovered || isSelected || isLifted ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(BlockText.help(block, name: block.displayName, people: people)))
        .accessibilityAction(named: Text("Edit"), edit)
    }

    private var background: AnyShapeStyle {
        if isLifted { return AnyShapeStyle(.background) }
        return isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.fill.quaternary)
    }
}
