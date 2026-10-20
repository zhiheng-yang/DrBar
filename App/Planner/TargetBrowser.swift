import DrBarKit
import SwiftUI

/// Chooses where a paper will be submitted: the conference list in a sheet, with the paper's
/// edition selected, and Cancel and Choose.
struct TargetBrowser: View {
    let paperID: UUID
    /// The planner window's, where what is chosen here is undone.
    let undoManager: UndoManager?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ConferenceBrowser(current: target, windowUndoManager: undoManager) { choice in
            // Choosing the paper's own edition again keeps the round fixed for it.
            if choice.id != target.map(TargetChoice.id(of:)) {
                store.setTarget(choice.target, of: paperID, undoManager: undoManager)
            }
            dismiss()
        }
        .frame(width: 1080, height: 680)
    }

    private var target: Paper.Target? {
        store.userData.papers.first { $0.id == paperID }?.target
    }
}
