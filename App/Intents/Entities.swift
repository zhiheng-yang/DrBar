import AppIntents
import DrBarKit
import DrBarUI

/// A paper or an item, as Siri, Shortcuts and Spotlight know it: by its title, under its group.
struct WorkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Paper or Item"
    static let defaultQuery = WorkQuery()

    let id: UUID
    let title: String
    /// "Papers", or the name of its group.
    let group: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(group)", image: .init(systemName: symbol))
    }

    @MainActor
    init(_ paper: Paper, in store: AppStore) {
        id = paper.id
        title = paper.displayTitle
        group = store.groupName(paper.groupID)
        symbol = store.userData.symbol(of: paper)
    }

    /// The papers and items in the order of the sidebar; not those archived or deleted.
    @MainActor
    static var all: [WorkEntity] {
        let store = AppStore.shared
        return store.userData.groupOrder.flatMap { store.userData.items(in: $0) }.map { WorkEntity($0, in: store) }
    }
}

struct WorkQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WorkEntity] {
        WorkEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [WorkEntity] {
        WorkEntity.all.filter { $0.title.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkEntity] {
        WorkEntity.all
    }
}

/// Papers, or one of the user's groups.
struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Group"
    static let defaultQuery = GroupQuery()

    /// "papers", or the group's id.
    let id: String
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    var groupID: UUID? {
        UUID(uuidString: id)
    }

    /// Papers and the groups, in the order of the sidebar.
    @MainActor
    static var all: [GroupEntity] {
        let store = AppStore.shared
        return store.userData.groupOrder.map { groupID in
            GroupEntity(
                id: groupID?.uuidString ?? "papers", name: store.groupName(groupID),
                symbol: store.userData.groups.first { $0.id == groupID }?.shownSymbol ?? "doc.text")
        }
    }
}

struct GroupQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [GroupEntity] {
        GroupEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroupEntity] {
        GroupEntity.all.filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GroupEntity] {
        GroupEntity.all
    }
}

/// A block of a paper's or an item's plan, named as on its bar, with its paper and its days. Siri
/// is told the paper and asks for the block, since every plan has blocks of the same names.
struct BlockEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Block"
    static let defaultQuery = BlockQuery()

    let id: UUID
    let paperID: UUID
    let name: String
    let paperTitle: String
    let days: String
    let isDone: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(paperTitle) · \(days)")
    }

    @MainActor
    init(_ block: TimeBlock, of paper: Paper) {
        id = block.id
        paperID = paper.id
        name = block.displayName
        paperTitle = paper.displayTitle
        days = BlockText.range(block)
        isDone = block.isDone
    }

    /// The blocks of every paper and item, each plan in the order of its days.
    @MainActor
    static var all: [BlockEntity] {
        let store = AppStore.shared
        return store.userData.groupOrder.flatMap { store.userData.items(in: $0) }.flatMap { paper in
            paper.blocks.sorted { $0.start < $1.start }.map { BlockEntity($0, of: paper) }
        }
    }
}

struct BlockQuery: EntityStringQuery {
    @IntentParameterDependency<MoveBlockIntent>(\.$work) var moving
    @IntentParameterDependency<EndBlockIntent>(\.$work) var ending
    @IntentParameterDependency<MarkBlockDoneIntent>(\.$work) var finishing

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BlockEntity] {
        BlockEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [BlockEntity] {
        blocks.filter { $0.name.localizedStandardContains(string) || $0.paperTitle.localizedStandardContains(string) }
    }

    /// Those not done yet.
    @MainActor
    func suggestedEntities() async throws -> [BlockEntity] {
        blocks.filter { !$0.isDone }
    }

    /// The blocks of the paper or item the intent is about, once it is known.
    @MainActor
    private var blocks: [BlockEntity] {
        guard let work = moving?.work ?? ending?.work ?? finishing?.work else { return BlockEntity.all }
        return BlockEntity.all.filter { $0.paperID == work.id }
    }
}

/// The kinds of work a block can be, as Siri names them.
enum WorkKind: String, AppEnum {
    case experiments, writing, review, buffer

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kind of Work"
    static let caseDisplayRepresentations: [WorkKind: DisplayRepresentation] = [
        .experiments: "Experiments", .writing: "Writing",
        .review: DisplayRepresentation(title: "Internal review", synonyms: ["Review", "Revision"]), .buffer: "Buffer",
    ]

    var kind: TimeBlock.Kind {
        switch self {
        case .experiments: .experiments
        case .writing: .writing
        case .review: .review
        case .buffer: .buffer
        }
    }
}

/// What an intent says when it cannot do what it was asked.
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    /// What it was asked about is gone.
    case notFound
    /// Every block of the paper or item with that title is done, or it has none.
    case nothingLeft(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: "It is no longer in DrBar."
        case let .nothingLeft(title): "“\(title)” has no blocks left to do."
        }
    }
}
