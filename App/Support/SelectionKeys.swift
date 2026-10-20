import AppKit
import SwiftUI

extension FocusState<Bool>.Binding {
    /// Gives the keys to the view this binding focuses, once something on it is clicked. While a list
    /// such as the sidebar, a text field or another control of AppKit holds them, SwiftUI only marks
    /// the view focused and the keys still go to the holder, so that it gives them up first.
    @MainActor
    func takeKeys() {
        guard let window = NSApp.keyWindow, let holder = window.firstResponder,
            holder is NSText || holder is NSTableView || holder is NSControl
        else {
            wrappedValue = true
            return
        }
        window.makeFirstResponder(nil)
        Task { wrappedValue = true }
    }
}

/// The keys of a list on a paper's page whose rows select what they show: once a row is clicked
/// the list has the focus, without a ring, and Delete deletes what is selected, as on the
/// timeline; Esc lets it go.
struct SelectionKeys: ViewModifier {
    var isFocused: FocusState<Bool>.Binding
    /// Deletes what is selected, if it is in the list; returns whether it was.
    let delete: () -> Bool
    /// Lets the selection go, if it is in the list; returns whether it was.
    let deselect: () -> Bool

    func body(content: Content) -> some View {
        content
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused(isFocused)
            .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { _ in delete() ? .handled : .ignored }
            .onKeyPress(.escape, phases: .down) { _ in deselect() ? .handled : .ignored }
    }
}
