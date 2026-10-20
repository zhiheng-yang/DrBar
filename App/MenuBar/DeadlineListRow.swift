import DrBarKit
import DrBarUI
import SwiftUI

/// A conference row of the menu bar window: a highlight under the pointer, its whole cycle in a
/// hover card, and a click to show the details. Quiet under papers and groups.
struct DeadlineListRow: View {
    let row: DeadlineRow
    let axis: TimeAxis
    var isQuiet = false
    let metrics: RowMetrics
    let select: () -> Void

    @Environment(AppStore.self) private var store
    @State private var isHovered = false

    var body: some View {
        DeadlineRowView(
            row: row, axis: axis, now: store.now, metrics: metrics, isQuiet: isQuiet,
            card: store.card(for: row, isQuiet: isQuiet)
        )
        .rowChrome(isHovered: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: select)
    }
}
