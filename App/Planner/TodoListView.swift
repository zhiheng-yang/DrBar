import DrBarKit
import DrBarUI
import SwiftUI

/// A paper's to-dos as a short checklist, as Reminders keeps one: tick the circle when done, click
/// a to-do to edit it in place, drag it to another place, and type into the last line to add one.
/// A to-do left empty is removed.
struct TodoListView: View {
    @Binding var todos: [TodoItem]
    let paperID: UUID

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @FocusState private var focus: TodoField?
    /// Waits for the field of a to-do clicked into to take the focus, to put the caret in it.
    @State private var caretPlacement: NSKeyValueObservation?
    @State private var reorder: RowMove?
    /// Set by Esc during a reorder, until the button comes up.
    @State private var isReorderCancelled = false
    @State private var cancellation = DragCancellation()
    /// From the top of one row to the top of the next, divider included.
    @State private var pitch: CGFloat = 37

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                row(todo, at: index)
            }
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 17)
                TextField("New To-Do", text: $draft, prompt: Text("New To-Do"))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .draft)
                    .onSubmit(add)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .onChange(of: focus) { old, _ in
            if case let .todo(id) = old, let todo = todos.first(where: { $0.id == id }),
                todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                withAnimation(reduceMotion ? nil : .settle) { todos.removeAll { $0.id == id } }
            }
        }
    }

    private func row(_ todo: TodoItem, at index: Int) -> some View {
        let isLifted = reorder?.from == index
        return VStack(spacing: 0) {
            TodoRow(
                todo: Binding($todos, id: todo.id, fallback: todo), focus: $focus,
                takesClicks: focus == .todo(todo.id), isLifted: isLifted,
                toggle: { toggle(todo) })
            Divider()
                .padding(.leading, 34)
                .opacity(reorder == nil ? 1 : 0)
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            if index == 0 { pitch = height }
        }
        .offset(y: reorder?.offset(ofRowAt: index, rowHeight: pitch, count: todos.count) ?? 0)
        .zIndex(isLifted ? 1 : 0)
        .animation(
            isLifted || reduceMotion ? nil : .makeRoom,
            value: reorder?.destination(rowHeight: pitch, count: todos.count)
        )
        .onTapGesture { edit(todo.id) }
        .gesture(reorderGesture(from: index))
        .contextMenu {
            Button("Delete") { delete(todo) }
        }
        .accessibilityAction(named: Text("Move Up")) { move(todo.id, by: -1) }
        .accessibilityAction(named: Text("Move Down")) { move(todo.id, by: 1) }
    }

    /// Starts editing a to-do with the caret where the click landed in its text, or at its end for a
    /// click beside the text. Focusing a field selects all of it, which the next key would type over,
    /// so the caret is put in place once the field's editor has taken over.
    private func edit(_ id: TodoItem.ID) {
        guard let title = todos.first(where: { $0.id == id })?.title else { return }
        let event = NSApp.currentEvent
        let click = event?.type == .leftMouseUp ? event?.locationInWindow : nil
        caretPlacement = (event?.window ?? NSApp.keyWindow)?.observe(\.firstResponder) { window, _ in
            MainActor.assumeIsolated {
                guard let editor = window.firstResponder as? NSTextView, editor.string == title else { return }
                let point = click.map { editor.convert($0, from: nil) }
                let location =
                    point.flatMap { editor.bounds.contains($0) ? editor.characterIndexForInsertion(at: $0) : nil }
                    ?? editor.string.utf16.count
                // After the field has selected all of itself.
                Task { editor.setSelectedRange(NSRange(location: location, length: 0)) }
                caretPlacement = nil
            }
        }
        focus = .todo(id)
    }

    /// Dragging a to-do: it follows the pointer, the others make room, and on release it settles
    /// into its new place.
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
                let landing = move.destination(rowHeight: pitch, count: todos.count)
                let order = move.apply(to: todos.map(\.id), rowHeight: pitch)
                withAnimation(reduceMotion ? nil : .drop) {
                    reorder?.translation = Double(landing - index) * pitch
                } completion: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        reorder = nil
                        store.setTodoOrder(order, in: paperID, undoManager: undoManager)
                    }
                }
            }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .settle) {
            store.addTodo(TodoItem(title: title), to: paperID, undoManager: undoManager)
        }
        draft = ""
        focus = .draft
    }

    private func toggle(_ todo: TodoItem) {
        withAnimation(reduceMotion ? nil : .glide) {
            store.setDone(!todo.isDone, ofTodo: todo.id, in: paperID, undoManager: undoManager)
        }
    }

    private func delete(_ todo: TodoItem) {
        withAnimation(reduceMotion ? nil : .settle) {
            store.deleteTodo(todo.id, undoManager: undoManager)
        }
    }

    private func move(_ id: TodoItem.ID, by offset: Int) {
        guard let index = todos.firstIndex(where: { $0.id == id }), todos.indices.contains(index + offset) else {
            return
        }
        var order = todos.map(\.id)
        order.swapAt(index, index + offset)
        store.setTodoOrder(order, in: paperID, undoManager: undoManager)
    }
}

private enum TodoField: Hashable {
    case todo(TodoItem.ID)
    case draft
}

/// Circle · title. The title takes clicks only while it is being edited, so that the row can be
/// dragged by it.
private struct TodoRow: View {
    @Binding var todo: TodoItem
    var focus: FocusState<TodoField?>.Binding
    let takesClicks: Bool
    let isLifted: Bool
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Button(action: toggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(todo.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .symbolEffect(.bounce, value: reduceMotion ? false : todo.isDone)
            }
            .buttonStyle(.borderless)
            .help(todo.isDone ? Text("Mark as not done") : Text("Mark as done"))
            .accessibilityLabel(todo.isDone ? Text("Done") : Text("Not done"))
            TextField("To-Do", text: $todo.title)
                .textFieldStyle(.plain)
                .foregroundStyle(todo.isDone ? .secondary : .primary)
                .focused(focus, equals: .todo(todo.id))
                .onSubmit { focus.wrappedValue = .draft }
                .allowsHitTesting(takesClicks)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .opacity(isLifted ? 1 : 0)
        }
        .contentShape(Rectangle())
    }
}
