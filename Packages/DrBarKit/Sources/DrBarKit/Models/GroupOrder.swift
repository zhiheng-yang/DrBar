import Foundation

/// A row of the sidebar's single column of groups: the heading of a group, `nil` for the papers,
/// or an item under it.
public enum SidebarRow: Hashable, Sendable {
    case heading(UUID?)
    case item(UUID)

    public var isHeading: Bool {
        if case .heading = self { true } else { false }
    }
}

extension UserData {
    /// The groups in the order of the sidebar, with `nil` where the papers come. Setting it puts
    /// the groups in that order; groups it leaves out follow the others.
    public var groupOrder: [UUID?] {
        get {
            var order: [UUID?] = groups.map(\.id)
            order.insert(nil, at: min(max(papersPosition, 0), groups.count))
            return order
        }
        set {
            var rest = groups
            var ordered: [ItemGroup] = []
            var position: Int?
            for id in newValue {
                if let id {
                    if let index = rest.firstIndex(where: { $0.id == id }) {
                        ordered.append(rest.remove(at: index))
                    }
                } else if position == nil {
                    position = ordered.count
                }
            }
            groups = ordered + rest
            papersPosition = position ?? min(papersPosition, groups.count)
        }
    }

    /// Puts a group into the sidebar at `position` of `groupOrder`.
    public mutating func insertGroup(_ group: ItemGroup, at position: Int) {
        var order = groupOrder
        order.insert(group.id, at: min(max(position, 0), order.count))
        groups.append(group)
        groupOrder = order
    }

    /// Takes a group out of the sidebar, with where it was in `groupOrder`. Its items stay.
    @discardableResult
    public mutating func removeGroup(_ id: UUID) -> (group: ItemGroup, position: Int)? {
        guard let index = groups.firstIndex(where: { $0.id == id }), let position = groupOrder.firstIndex(of: id)
        else { return nil }
        var order = groupOrder
        order.remove(at: position)
        let group = groups.remove(at: index)
        groupOrder = order
        return (group, position)
    }

    /// Each group's heading followed by its items, in the order of the sidebar.
    public var sidebarRows: [SidebarRow] {
        groupOrder.flatMap { groupID in
            [.heading(groupID)] + items(in: groupID).map { .item($0.id) }
        }
    }

    /// Puts the groups in the order of the headings of `rows`, and each item into the group of the
    /// heading above it, in its place there. Whatever `rows` leaves out keeps its group, after the
    /// others.
    public mutating func arrange(_ rows: [SidebarRow]) {
        let known = Set(groups.map(\.id))
        var order: [UUID?] = []
        var placed: [(id: UUID, groupID: UUID?)] = []
        var groupID: UUID?
        for row in rows {
            switch row {
            case let .heading(id):
                // A group that has gone since lets its items go to the papers.
                groupID = id.flatMap { known.contains($0) ? $0 : nil }
                if groupID == id {
                    order.append(id)
                }
            case let .item(id):
                placed.append((id, groupID))
            }
        }
        var rest = papers
        var arranged: [Paper] = []
        for (id, groupID) in placed {
            guard let index = rest.firstIndex(where: { $0.id == id }) else { continue }
            var paper = rest.remove(at: index)
            paper.groupID = groupID
            arranged.append(paper)
        }
        papers = arranged + rest
        groupOrder = order
    }
}

extension [SidebarRow] {
    /// The rows once those at `source` are dragged to `destination`, an index of the rows as they
    /// were, as a list moves them: an item joins the group it is dropped in, and a heading takes its
    /// items along to the nearest place between two groups.
    public func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> [SidebarRow] {
        guard let first = source.first, indices.contains(first) else { return self }
        if self[first].isHeading {
            return movingGroup(at: first, to: destination)
        }
        let moved = source.filter { indices.contains($0) && !self[$0].isHeading }
        var rows = self
        for index in moved.reversed() {
            rows.remove(at: index)
        }
        let target = destination - moved.filter { $0 < destination }.count
        rows.insert(contentsOf: moved.map { self[$0] }, at: Swift.min(Swift.max(target, 0), rows.count))
        // Nothing goes above the first heading: an item dropped there is the first of its group.
        if let heading = rows.firstIndex(where: \.isHeading), heading > 0 {
            let above = rows[..<heading]
            rows.removeSubrange(..<heading)
            rows.insert(contentsOf: above, at: 1)
        }
        return rows
    }

    /// The rows once the item `id` is dragged among `shown`, some of them in their order, to index
    /// `destination` of `shown` as it is without the item: it lands after the row shown above that
    /// place, into that row's group, and the rows that are not shown keep their places.
    public func moving(item id: UUID, to destination: Int, among shown: [SidebarRow]) -> [SidebarRow] {
        guard let source = firstIndex(of: .item(id)) else { return self }
        let others = shown.filter { $0 != .item(id) }
        let above = destination > 0 && !others.isEmpty ? others[Swift.min(destination, others.count) - 1] : nil
        guard let above, let anchor = firstIndex(of: above) else {
            return moving(fromOffsets: [source], toOffset: 0)
        }
        return moving(fromOffsets: [source], toOffset: anchor + 1)
    }

    private func movingGroup(at index: Int, to destination: Int) -> [SidebarRow] {
        let end = self[(index + 1)...].firstIndex(where: \.isHeading) ?? endIndex
        guard destination < index || destination > end else { return self }
        let group = self[index..<end]
        var rows = self
        rows.removeSubrange(index..<end)
        let target = destination > end ? destination - group.count : destination
        rows.insert(contentsOf: group, at: rows.boundary(nearest: target, isUp: destination < index))
        return rows
    }

    /// The place between two groups, or at either end, nearest to `index`; on a tie the upper one
    /// when the drag went up.
    private func boundary(nearest index: Int, isUp: Bool) -> Int {
        let boundaries = indices.filter { self[$0].isHeading } + [count]
        guard let below = boundaries.first(where: { $0 >= index }) else { return count }
        guard let above = boundaries.last(where: { $0 <= index }) else { return below }
        let (up, down) = (index - above, below - index)
        return up < down || (up == down && isUp) ? above : below
    }
}
