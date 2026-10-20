import DrBarKit
import DrBarUI
import SwiftUI

/// The papers, or the items of one group, as the overview and the menu bar window list them, under
/// the group's name.
struct ItemSection: Identifiable {
    let groupID: UUID?
    let title: String
    let items: [Paper]

    var id: String {
        groupID?.uuidString ?? "papers"
    }

    /// The work with blocks, each in a row of its own.
    var planned: [Paper] {
        items.filter { !$0.blocks.isEmpty }
    }

    /// The work without blocks, whose deadlines share the line of the group's name.
    var unplanned: [Paper] {
        items.filter(\.blocks.isEmpty)
    }
}

extension [ItemSection] {
    /// What moves when a paper or an item is dragged by its name: every title but the first, which
    /// carries the axis, and every paper and item with a row, so that a row can pass a title into
    /// another group.
    var movableRows: [SidebarRow] {
        enumerated().flatMap { number, section in
            (number == 0 ? [] : [SidebarRow.heading(section.groupID)]) + section.planned.map { .item($0.id) }
        }
    }
}

extension AppStore {
    /// The papers and each group's items, in the sidebar's order, leaving out what has none;
    /// with `hidesFinished`, without the items that are done and the papers that are decided,
    /// unless one still has a deadline of its own ahead, such as a camera-ready.
    func itemSections(hidesFinished: Bool = false) -> [ItemSection] {
        userData.groupOrder.compactMap { groupID in
            let items = userData.items(in: groupID).filter { item in
                !hidesFinished || item.isUnderWay(overview(for: item).deadlines, now: now)
            }
            return items.isEmpty ? nil : ItemSection(groupID: groupID, title: groupName(groupID), items: items)
        }
    }

    /// Puts a paper or an item dragged by its name where it lands, at `destination` of the movable
    /// rows of `sections`: into the group of the title or the row above it.
    func drop(_ id: UUID, at destination: Int, in sections: [ItemSection], undoManager: UndoManager?) {
        guard let first = sections.first else { return }
        let shown = [SidebarRow.heading(first.groupID)] + sections.movableRows
        arrange(userData.sidebarRows.moving(item: id, to: destination + 1, among: shown), undoManager: undoManager)
    }

    /// The hover card of a paper's or an item's name, from the `overview` its row shows, or of its
    /// flag where it has no row.
    func card(for paper: Paper, overview: PaperOverview, hasRow: Bool = true) -> HoverCardSource {
        HoverCardSource(id: paper.id.uuidString) { [self] in
            .paper(paper, overview: overview, people: userData.people, now: now, hasRow: hasRow)
        }
    }

    /// The work without blocks of `section`, as its line shows it.
    func dueWork(of section: ItemSection) -> [DueWork] {
        section.unplanned.map { DueWork(id: $0.id, title: $0.displayTitle, overview: overview(for: $0)) }
    }

    /// The hover card of a flag of a group's line: the card of its work.
    func dueCard(_ id: UUID) -> HoverCardSource? {
        userData.papers.first { $0.id == id }.map { card(for: $0, overview: overview(for: $0), hasRow: false) }
    }

    /// The hover card of a conference row, with what the catalog adds to the row, and with what a
    /// `isQuiet` row leaves out.
    func card(for row: DeadlineRow, isQuiet: Bool) -> HoverCardSource {
        HoverCardSource(id: row.id) { [self] in
            guard let (series, edition) = catalog.edition(id: row.source.edition) else {
                return .conference(row, series: nil, round: nil, edition: nil, isQuiet: isQuiet, now: now)
            }
            let round = edition.rounds.first { $0.id == row.source.round }
            return .conference(row, series: series, round: round, edition: edition, isQuiet: isQuiet, now: now)
        }
    }

    /// Papers, or the name of the group with `groupID`.
    func groupName(_ groupID: UUID?) -> String {
        guard let groupID else { return String(localized: "Papers") }
        return userData.groups.first { $0.id == groupID }?.displayName ?? ""
    }
}

extension View {
    /// Draws one of a column of rows being reordered where `move` puts it: the dragged one under
    /// the pointer and above the others, which step aside to make room.
    func reordering(_ index: Int?, by move: RowMove?, heights: [Double]) -> some View {
        modifier(Reordering(index: index, move: move, heights: heights))
    }
}

private struct Reordering: ViewModifier {
    let index: Int?
    let move: RowMove?
    let heights: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isLifted = index != nil && move?.from == index
        content
            .offset(y: index.flatMap { move?.offset(ofRowAt: $0, heights: heights) } ?? 0)
            .zIndex(isLifted ? 1 : 0)
            .animation(
                isLifted || reduceMotion ? nil : .makeRoom, value: move?.destination(heights: heights))
    }
}
