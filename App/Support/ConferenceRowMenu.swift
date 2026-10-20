import AppKit
import DrBarKit
import SwiftUI

/// What can be done with the row of a starred conference, wherever it is listed.
struct ConferenceRowMenu: View {
    let row: DeadlineRow
    let showDetails: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button("Show Details", action: showDetails)
        Button(store.isStarred(row.seriesKey) ? "Unstar" : "Star") {
            withAnimation(reduceMotion ? nil : .settle) { store.toggleStar(row.seriesKey, undoManager: undoManager) }
        }
        if let url = store.catalog.edition(id: row.source.edition)?.1.url {
            Button("Open Website") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Toggle("Show in Menu Bar", isOn: store.showsInMenuBar(.series(row.seriesKey)))
    }
}
