import Foundation

/// A group in the sidebar besides the papers, for other work with a deadline that the user keeps
/// together, such as applications or reviews. Its items are planned as papers are, without the
/// stages and the progress emails that only papers have.
public struct ItemGroup: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The SF Symbol its items are shown with, one of `symbols`; `nil` for the first of them.
    public var symbol: String?

    /// What a group's items can be shown with, as a list in Reminders is: a calendar to begin with.
    public static let symbols = [
        "calendar", "list.bullet.clipboard", "magnifyingglass", "envelope", "briefcase", "studentdesk", "trophy",
        "banknote", "airplane", "person.2", "mic", "book",
    ]

    public init(id: UUID = UUID(), name: String, symbol: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    /// The symbol its items are shown with.
    public var shownSymbol: String {
        symbol.flatMap { Self.symbols.contains($0) ? $0 : nil } ?? Self.symbols[0]
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        name = c(.name, default: "")
        symbol = c(.symbol, default: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(symbol, forKey: .symbol)
    }
}

extension UserData {
    /// The papers, or the items of the group with `groupID`, in their order.
    public func items(in groupID: UUID?) -> [Paper] {
        papers.filter { $0.groupID == groupID }
    }

    /// Whether a group has items, archived ones too, which deleting it sends to Recently Deleted.
    public func hasItems(inGroup groupID: UUID) -> Bool {
        (papers + archive).contains { $0.groupID == groupID }
    }

    /// What a paper is shown with, a page; or an item, its group's symbol, wherever it is.
    public func symbol(of paper: Paper, deletedWith group: ItemGroup? = nil) -> String {
        guard let groupID = paper.groupID else { return "doc.text" }
        return (groups.first { $0.id == groupID } ?? group)?.shownSymbol ?? ItemGroup.symbols[0]
    }

    /// Earlier builds kept a list of deadlines that stood on their own next to the starred
    /// conferences. Each becomes someone's own: that of every paper that aimed at it, wherever it is, or else that
    /// of a new item, in a new group named `name`, so that it can be planned like a paper; the item
    /// takes the deadline's name. A menu bar that showed one of them shows its paper or item
    /// instead. Returns whether anything changed.
    @discardableResult
    public mutating func moveListedDeadlines(intoGroupNamed name: String) -> Bool {
        guard !listedDeadlines.isEmpty else { return false }
        var group: ItemGroup?
        for deadline in listedDeadlines {
            // Those that aim at it, wherever they are: the first takes it, each other one a copy.
            var owner: UUID?
            updateEveryPaper { paper in
                guard owner == nil, paper.mainDeadline == deadline.id,
                    !paper.deadlines.contains(where: { $0.id == deadline.id })
                else { return }
                owner = paper.id
                paper.deadlines.append(deadline)
            }
            giveCopies(of: deadline)
            if owner == nil {
                let newGroup = group ?? ItemGroup(name: name)
                group = newGroup
                var own = deadline
                own.title = ""
                let item = Paper(title: deadline.title, deadlines: [own], mainDeadline: own.id, groupID: newGroup.id)
                papers.append(item)
                owner = item.id
            }
            if let owner, settings.menuBarSubject == .customDeadline(deadline.id) {
                settings.menuBarSubject = .paper(owner)
            }
        }
        listedDeadlines = []
        if let group {
            groups.append(group)
        }
        return true
    }
}
