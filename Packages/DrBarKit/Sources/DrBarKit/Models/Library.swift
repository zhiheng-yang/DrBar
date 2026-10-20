import Foundation

/// What Recently Deleted keeps: anything deleted, for thirty days, as Notes and Photos keep it.
public protocol RecentlyDeleted {
    var deletedAt: Date { get }
}

extension RecentlyDeleted {
    /// How many days Recently Deleted keeps what is deleted.
    public static var keptDays: Int {
        30
    }

    /// When it is deleted for good.
    public var expiry: Date {
        deletedAt.addingTimeInterval(Double(Self.keptDays) * 86_400)
    }

    /// The days left before it is deleted for good, rounded up: 30 on the day it was deleted.
    public func daysLeft(now: Date) -> Int {
        min(max(Int((expiry.timeIntervalSince(now) / 86_400).rounded(.up)), 0), Self.keptDays)
    }
}

/// A paper or an item in Recently Deleted, with everything it had.
public struct DeletedPaper: RecentlyDeleted, Codable, Identifiable, Hashable, Sendable {
    public var paper: Paper
    /// Its group, when the whole group was deleted, so that it comes back into it, and where the
    /// group was among the others.
    public var group: ItemGroup?
    public var groupPosition: Int
    public var deletedAt: Date
    /// Whether it was in the Archive, where it goes back.
    public var wasArchived: Bool
    /// Where it was in its list, where it goes back.
    public var index: Int

    public var id: UUID {
        paper.id
    }

    public init(
        paper: Paper, group: ItemGroup? = nil, groupPosition: Int = 0, deletedAt: Date, wasArchived: Bool = false,
        index: Int = 0
    ) {
        self.paper = paper
        self.group = group
        self.groupPosition = groupPosition
        self.deletedAt = deletedAt
        self.wasArchived = wasArchived
        self.index = index
    }

    enum CodingKeys: String, CodingKey {
        case paper, group, groupPosition, deletedAt, wasArchived, index
        /// Its own deadlines, which the first builds with Recently Deleted kept beside it.
        case deadlines
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        var paper: Paper = try c.required(.paper)
        let deadlines: [CustomDeadline] = c.list(.deadlines)
        paper.deadlines += deadlines.filter { deadline in !paper.deadlines.contains { $0.id == deadline.id } }
        self.paper = paper
        group = c(.group, default: nil)
        groupPosition = c(.groupPosition, default: 0)
        deletedAt = c(.deletedAt, default: Date())
        wasArchived = c(.wasArchived, default: false)
        index = max(c(.index, default: 0), 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paper, forKey: .paper)
        try c.encodeIfPresent(group, forKey: .group)
        try c.encode(groupPosition, forKey: .groupPosition)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encode(wasArchived, forKey: .wasArchived)
        try c.encode(index, forKey: .index)
    }
}

/// A block, milestone, deadline or to-do deleted from a paper or an item, in Recently Deleted until
/// it goes back into it, at its place.
public struct DeletedPart: RecentlyDeleted, Codable, Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case block(TimeBlock)
        case milestone(Milestone)
        /// With whether the paper aimed at it, to aim at it again.
        case deadline(CustomDeadline, wasMain: Bool)
        case todo(TodoItem)

        public var id: UUID {
            switch self {
            case let .block(block): block.id
            case let .milestone(milestone): milestone.id
            case let .deadline(deadline, _): deadline.id
            case let .todo(todo): todo.id
            }
        }
    }

    public var content: Content
    /// The paper or the item it was part of.
    public var paperID: UUID
    /// Where it was in its list.
    public var index: Int
    public var deletedAt: Date

    public var id: UUID {
        content.id
    }

    public init(_ content: Content, paperID: UUID, index: Int, deletedAt: Date) {
        self.content = content
        self.paperID = paperID
        self.index = index
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case block, milestone, deadline, todo, wasMain, paperID, index, deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        if let block: TimeBlock = c(.block, default: nil) {
            content = .block(block)
        } else if let milestone: Milestone = c(.milestone, default: nil) {
            content = .milestone(milestone)
        } else if let deadline: CustomDeadline = c(.deadline, default: nil) {
            content = .deadline(deadline, wasMain: c(.wasMain, default: false))
        } else {
            content = .todo(try c.required(.todo))
        }
        paperID = try c.required(.paperID)
        index = max(c(.index, default: 0), 0)
        deletedAt = c(.deletedAt, default: Date())
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch content {
        case let .block(block):
            try c.encode(block, forKey: .block)
        case let .milestone(milestone):
            try c.encode(milestone, forKey: .milestone)
        case let .deadline(deadline, wasMain):
            try c.encode(deadline, forKey: .deadline)
            try c.encode(wasMain, forKey: .wasMain)
        case let .todo(todo):
            try c.encode(todo, forKey: .todo)
        }
        try c.encode(paperID, forKey: .paperID)
        try c.encode(index, forKey: .index)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

/// A row of Recently Deleted: a paper or an item, or a part of one.
public enum DeletedEntry: RecentlyDeleted, Identifiable, Hashable, Sendable {
    case paper(DeletedPaper)
    case part(DeletedPart)

    public var id: UUID {
        switch self {
        case let .paper(entry): entry.id
        case let .part(entry): entry.id
        }
    }

    public var deletedAt: Date {
        switch self {
        case let .paper(entry): entry.deletedAt
        case let .part(entry): entry.deletedAt
        }
    }
}

/// What `UserData.recover` brought back, for `putBack` to return it to Recently Deleted as it was
/// there: its time left, its group and the deadline its paper aimed at.
public struct Recovery: Sendable {
    /// The entries taken out of Recently Deleted, each with where it was in its list.
    fileprivate var papers: [(index: Int, entry: DeletedPaper)] = []
    fileprivate var parts: [(index: Int, entry: DeletedPart)] = []
    /// The groups that came back with their items.
    fileprivate var groups: [UUID] = []
    /// What each paper aimed at before a deadline came back to be aimed at again.
    fileprivate var aims: [UUID: UUID?] = [:]

    /// Everything that came back, the parts first.
    public var ids: [UUID] {
        parts.map(\.entry.id) + papers.map(\.entry.id)
    }
}

extension UserData {
    /// Everything in Recently Deleted, the last deleted first.
    public var deletedEntries: [DeletedEntry] {
        let entries = recentlyDeleted.map(DeletedEntry.paper) + deletedParts.map(DeletedEntry.part)
        // Within the same moment, the later in its list first.
        return entries.enumerated()
            .sorted { ($0.element.deletedAt, $0.offset) > ($1.element.deletedAt, $1.offset) }
            .map(\.element)
    }

    public var hasDeletedEntries: Bool {
        !recentlyDeleted.isEmpty || !deletedParts.isEmpty
    }

    /// Whether a paper or an item with `id` is anywhere: in its group, the Archive or Recently
    /// Deleted.
    public func contains(_ id: UUID) -> Bool {
        papers.contains { $0.id == id } || archive.contains { $0.id == id } || recentlyDeleted.contains { $0.id == id }
    }

    /// Moves papers or items, from their group or from the Archive, or blocks, milestones, deadlines
    /// or to-dos of a paper or an item, to Recently Deleted. Returns the ids of those it found.
    @discardableResult
    public mutating func delete(_ ids: [UUID], now: Date) -> [UUID] {
        let paperIDs = Set((papers + archive).map(\.id))
        var deleted: [UUID] = []
        // The parts first, while their papers are still there.
        for id in ids where !paperIDs.contains(id) {
            if deletePart(id, now: now) {
                deleted.append(id)
            }
        }
        let found = ids.filter(paperIDs.contains)
        delete(found, group: nil, at: 0, now: now)
        return deleted + found
    }

    /// Takes a block, milestone, deadline or to-do out of its paper or item into Recently Deleted.
    /// When the paper aimed at the deadline, it aims at its next own one, as when it is deleted.
    private mutating func deletePart(_ id: UUID, now: Date) -> Bool {
        guard let (paperID, content, index) = takeOutPart(id, now: now) else { return false }
        deletedParts.append(DeletedPart(content, paperID: paperID, index: index, deletedAt: now))
        return true
    }

    /// Takes a part out of its paper or item, wherever that is, with where it was.
    private mutating func takeOutPart(_ id: UUID, now: Date) -> (UUID, DeletedPart.Content, Int)? {
        var found: (UUID, DeletedPart.Content, Int)?
        let take = { (paper: inout Paper) in
            guard found == nil else { return }
            if let i = paper.blocks.firstIndex(where: { $0.id == id }) {
                found = (paper.id, .block(paper.blocks.remove(at: i)), i)
            } else if let i = paper.milestones.firstIndex(where: { $0.id == id }) {
                found = (paper.id, .milestone(paper.milestones.remove(at: i)), i)
            } else if let i = paper.deadlines.firstIndex(where: { $0.id == id }) {
                let wasMain = paper.mainDeadline == id
                found = (paper.id, .deadline(paper.deadlines.remove(at: i), wasMain: wasMain), i)
                if wasMain {
                    paper.mainDeadline = paper.ownDeadlineToAimAt(now: now)
                }
            } else if let i = paper.todos.firstIndex(where: { $0.id == id }) {
                found = (paper.id, .todo(paper.todos.remove(at: i)), i)
            }
        }
        for p in papers.indices where found == nil {
            take(&papers[p])
        }
        for p in archive.indices where found == nil {
            take(&archive[p])
        }
        return found
    }

    /// Deletes a group with its items, also those in the Archive, which go to Recently Deleted;
    /// the group waits there with them, to come back with the first of them that is recovered.
    /// Returns the items.
    @discardableResult
    public mutating func deleteGroup(_ id: UUID, now: Date) -> [UUID] {
        guard let (group, position) = removeGroup(id) else { return [] }
        let ids = (papers + archive).filter { $0.groupID == id }.map(\.id)
        delete(ids, group: group, at: position, now: now)
        return ids
    }

    private mutating func delete(_ ids: [UUID], group: ItemGroup?, at position: Int, now: Date) {
        for id in ids {
            guard let (paper, index, wasArchived) = removePaper(id) else { continue }
            recentlyDeleted.append(
                DeletedPaper(
                    paper: paper, group: group, groupPosition: position, deletedAt: now, wasArchived: wasArchived,
                    index: index))
        }
    }

    /// Brings papers, items or their parts back from Recently Deleted to where they were. A group
    /// that was deleted with its items comes back too, to its place; an item whose group is gone
    /// otherwise comes back among the papers. A part goes back into its paper or item, which comes
    /// back with it if it was deleted after it. The last deleted come back first, so that each
    /// finds its place. Returns what came back, for `putBack`.
    @discardableResult
    public mutating func recover(_ ids: [UUID]) -> Recovery {
        var ids = Set(ids)
        ids.formUnion(deletedParts.filter { ids.contains($0.id) }.map(\.paperID))
        var recovery = Recovery()
        for index in recentlyDeleted.indices.reversed() where ids.contains(recentlyDeleted[index].id) {
            let entry = recentlyDeleted.remove(at: index)
            restore(entry, into: &recovery)
            recovery.papers.append((index, entry))
        }
        for index in deletedParts.indices.reversed() where ids.contains(deletedParts[index].id) {
            let part = deletedParts[index]
            if restore(part, into: &recovery) {
                deletedParts.remove(at: index)
                recovery.parts.append((index, part))
            }
        }
        return recovery
    }

    private mutating func restore(_ entry: DeletedPaper, into recovery: inout Recovery) {
        var paper = entry.paper
        if let groupID = paper.groupID, !groups.contains(where: { $0.id == groupID }) {
            if let group = entry.group, group.id == groupID {
                insertGroup(group, at: entry.groupPosition)
                recovery.groups.append(groupID)
            } else {
                paper.groupID = nil
            }
        }
        if entry.wasArchived {
            archive.insert(paper, at: min(entry.index, archive.count))
        } else {
            papers.insert(paper, at: min(entry.index, papers.count))
        }
    }

    /// Puts a part back into its paper or item, wherever that is, at its place; a block without the
    /// people who have left the recipient groups since. Returns whether the paper was there.
    private mutating func restore(_ part: DeletedPart, into recovery: inout Recovery) -> Bool {
        let known = Set(people.keys)
        var aimedAt: UUID??
        func put(_ paper: inout Paper) {
            switch part.content {
            case var .block(block):
                block.people.removeAll { !known.contains($0) }
                paper.blocks.insert(block, at: min(part.index, paper.blocks.count))
            case let .milestone(milestone):
                paper.milestones.insert(milestone, at: min(part.index, paper.milestones.count))
            case let .deadline(deadline, wasMain):
                paper.deadlines.insert(deadline, at: min(part.index, paper.deadlines.count))
                if wasMain, paper.target == nil {
                    aimedAt = .some(paper.mainDeadline)
                    paper.mainDeadline = deadline.id
                }
            case let .todo(todo):
                paper.todos.insert(todo, at: min(part.index, paper.todos.count))
            }
        }
        guard updatePaper(part.paperID, put) else { return false }
        if let aimedAt, recovery.aims[part.paperID] == nil {
            recovery.aims.updateValue(aimedAt, forKey: part.paperID)
        }
        return true
    }

    /// Returns to Recently Deleted what `recover` brought back, each entry as it was there, with any
    /// change made to it since: the parts out of their papers, then the papers, then the groups that
    /// came back with them while they are empty. Returns the ids of those it found.
    @discardableResult
    public mutating func putBack(_ recovery: Recovery, now: Date) -> [UUID] {
        var found: [UUID] = []
        for (index, entry) in recovery.parts.sorted(by: { $0.index < $1.index }) {
            guard let (paperID, content, _) = takeOutPart(entry.id, now: now) else { continue }
            var part = entry
            switch (content, entry.content) {
            case let (.deadline(deadline, isMain), .deadline(_, wasMain)):
                part.content = .deadline(deadline, wasMain: wasMain)
                // The paper aims again at what it aimed at before the deadline came back.
                if isMain, let aim = recovery.aims[paperID] {
                    updatePaper(paperID) { $0.mainDeadline = aim }
                }
            default:
                part.content = content
            }
            deletedParts.insert(part, at: min(index, deletedParts.count))
            found.append(part.id)
        }
        for (index, entry) in recovery.papers.sorted(by: { $0.index < $1.index }) {
            guard let (paper, _, _) = removePaper(entry.id) else { continue }
            var deleted = entry
            deleted.paper = paper
            recentlyDeleted.insert(deleted, at: min(index, recentlyDeleted.count))
            found.append(deleted.id)
        }
        for groupID in recovery.groups where !hasItems(inGroup: groupID) {
            removeGroup(groupID)
        }
        return found
    }

    /// Changes a paper or an item, also one in the Archive; returns whether it was there.
    @discardableResult
    private mutating func updatePaper(_ id: UUID, _ update: (inout Paper) -> Void) -> Bool {
        if let p = papers.firstIndex(where: { $0.id == id }) {
            update(&papers[p])
        } else if let p = archive.firstIndex(where: { $0.id == id }) {
            update(&archive[p])
        } else {
            return false
        }
        return true
    }

    /// Takes a paper or an item out of the papers or the Archive, with where it was.
    private mutating func removePaper(_ id: UUID) -> (paper: Paper, index: Int, wasArchived: Bool)? {
        if let i = papers.firstIndex(where: { $0.id == id }) {
            return (papers.remove(at: i), i, false)
        }
        if let i = archive.firstIndex(where: { $0.id == id }) {
            return (archive.remove(at: i), i, true)
        }
        return nil
    }

    /// Deletes for good, with no way back, and with a paper or an item what was deleted from it
    /// before.
    public mutating func deleteForever(_ ids: Set<UUID>) {
        recentlyDeleted.removeAll { ids.contains($0.id) }
        deletedParts.removeAll { ids.contains($0.id) }
        dropOrphanedParts()
    }

    /// Deletes for good what has been in Recently Deleted for thirty days. Returns whether there
    /// was any.
    @discardableResult
    public mutating func purgeRecentlyDeleted(now: Date) -> Bool {
        let count = recentlyDeleted.count + deletedParts.count
        recentlyDeleted.removeAll { $0.expiry <= now }
        deletedParts.removeAll { $0.expiry <= now }
        dropOrphanedParts()
        return recentlyDeleted.count + deletedParts.count != count
    }

    /// Parts can go back only into a paper or an item that is still somewhere.
    public mutating func dropOrphanedParts() {
        let ids = Set(everyPaper.map(\.id))
        deletedParts.removeAll { !ids.contains($0.paperID) }
    }

    /// Puts a paper or an item away in the Archive, with everything it has, out of its group and
    /// the timelines. Returns where it was, for putting it back there.
    @discardableResult
    public mutating func archive(_ id: UUID, now: Date) -> Int? {
        guard let index = papers.firstIndex(where: { $0.id == id }) else { return nil }
        var paper = papers.remove(at: index)
        paper.archivedAt = now
        archive.append(paper)
        return index
    }

    /// Moves a paper or an item back from the Archive into its group, at `index` or at the end.
    public mutating func unarchive(_ id: UUID, at index: Int? = nil) {
        guard let position = archive.firstIndex(where: { $0.id == id }) else { return }
        var paper = archive.remove(at: position)
        paper.archivedAt = nil
        if let groupID = paper.groupID, !groups.contains(where: { $0.id == groupID }) {
            paper.groupID = nil
        }
        papers.insert(paper, at: min(index ?? papers.count, papers.count))
    }
}
