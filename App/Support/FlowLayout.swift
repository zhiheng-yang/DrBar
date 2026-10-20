import SwiftUI

/// Lays its subviews out in rows, as many to a row as fit, as text wraps, each centered on its
/// row's middle. A subview wider than a row gets the row's width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.items.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        return CGSize(width: width, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(of: subviews, width: proposal.width ?? bounds.width) {
            for item in row.items {
                // At its own size while it fits, so that its text is never cut short by rounding.
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(width: item.isNarrowed ? item.size.width : nil, height: nil))
            }
        }
    }

    private struct Row {
        var items: [Item] = []
        var y: CGFloat
        var height: CGFloat = 0
    }

    private struct Item {
        let index: Int
        let size: CGSize
        let x: CGFloat
        let isNarrowed: Bool
    }

    /// Where each subview goes, row by row, in a width of `width`.
    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row(y: 0)
        var x: CGFloat = 0
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let isNarrowed = ideal.width > width
            let size = isNarrowed ? subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
            if !row.items.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + lineSpacing)
                x = 0
            }
            row.items.append(Item(index: index, size: size, x: x, isNarrowed: isNarrowed))
            row.height = max(row.height, size.height)
            x += size.width + spacing
        }
        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
