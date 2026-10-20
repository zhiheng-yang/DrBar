import AppIntents
import DrBarKit
import DrBarUI

/// Adds a block of work to a plan: "Add a block to Video Diffusion in DrBar".
struct AddBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Block"
    static let description = IntentDescription(
        "Adds a block of work to the plan of a paper or an item: a kind of work, or one of your own naming.")

    @Parameter(title: "Paper or Item", requestValueDialog: "Which paper or item?")
    var work: WorkEntity

    @Parameter(title: "Kind of Work")
    var kind: WorkKind?

    @Parameter(title: "Start", kind: .date)
    var start: Date?

    @Parameter(title: "Days", default: 7, inclusiveRange: (1, 365), requestValueDialog: "For how many days?")
    var days: Int

    /// A name of its own, which makes it a block of that name rather than of a kind.
    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$kind) to \(\.$work) from \(\.$start) for \(\.$days) days") {
            \.$name
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard store.userData.papers.contains(where: { $0.id == work.id }) else { throw IntentFailure.notFound }
        let custom = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = custom.isEmpty ? try await $kind.value(asking: "What kind of work is it?").kind : .custom
        let first = Day(try await $start.value(asking: "When does it start?"))
        let block = TimeBlock(
            kind: kind, customName: custom, start: first, end: first.adding(min(max(days, 1), 365) - 1))
        store.addBlock(block, to: work.id, undoManager: nil)
        guard store.block(block.id) != nil else { throw IntentFailure.notFound }
        return .result(dialog: "Added \(block.displayName) to “\(work.title)”, \(BlockText.range(block)).")
    }
}

/// Moves a block to start on another day, keeping its length: "Move a block of Video Diffusion in
/// DrBar".
struct MoveBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Move a Block"
    static let description = IntentDescription("Moves a block of a plan to start on another day, keeping its length.")

    @Parameter(title: "Paper or Item", requestValueDialog: "Which paper or item?")
    var work: WorkEntity

    @Parameter(title: "Block")
    var block: BlockEntity?

    @Parameter(title: "Start", kind: .date)
    var start: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$block) of \(\.$work) to \(\.$start)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let old = try await store.blockToChange(block, of: work, asking: $block)
        let first = Day(try await $start.value(asking: "Which day should it start on?"))
        store.setDays(
            first, old.end.adding(old.start.days(to: first)), ofBlock: old.id, in: work.id,
            actionName: String(localized: "Move Block"), undoManager: nil)
        let moved = store.block(old.id)?.block ?? old
        return .result(dialog: "\(moved.displayName) of “\(work.title)” is now \(BlockText.range(moved)).")
    }
}

/// Makes a block end on another day, longer or shorter: "Extend a block of Video Diffusion in
/// DrBar".
struct EndBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Change When a Block Ends"
    static let description = IntentDescription("Makes a block of a plan end on another day, longer or shorter.")

    @Parameter(title: "Paper or Item", requestValueDialog: "Which paper or item?")
    var work: WorkEntity

    @Parameter(title: "Block")
    var block: BlockEntity?

    @Parameter(title: "End", kind: .date)
    var end: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("End \(\.$block) of \(\.$work) on \(\.$end)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let old = try await store.blockToChange(block, of: work, asking: $block)
        let last = Day(try await $end.value(asking: "Which day should it end on?"))
        store.setDays(
            old.start, max(last, old.start), ofBlock: old.id, in: work.id,
            actionName: String(localized: "Resize Block"), undoManager: nil)
        let changed = store.block(old.id)?.block ?? old
        return .result(dialog: "\(changed.displayName) of “\(work.title)” is now \(BlockText.range(changed)).")
    }
}

/// Ticks a block off: "Mark a block of Video Diffusion as done in DrBar".
struct MarkBlockDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a Block as Done"
    static let description = IntentDescription("Ticks a block of a plan off.")

    @Parameter(title: "Paper or Item", requestValueDialog: "Which paper or item?")
    var work: WorkEntity

    @Parameter(title: "Block")
    var block: BlockEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$block) of \(\.$work) as done")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let done = try await store.blockToChange(block, of: work, asking: $block)
        store.setDone(true, ofBlock: done.id, in: work.id, undoManager: nil)
        return .result(dialog: "\(done.displayName) of “\(work.title)” is done.")
    }
}

extension IntentParameter {
    /// The value given, or else the one Siri asks for with `dialog`.
    func value<Wrapped>(asking dialog: IntentDialog) async throws -> Wrapped
    where Value == Wrapped?, Value.ValueType == Wrapped {
        if let value = wrappedValue {
            return value
        }
        return try await requestValue(dialog)
    }
}

extension AppStore {
    /// A block of a paper or an item, with whose it is.
    func block(_ id: UUID) -> (paperID: UUID, block: TimeBlock)? {
        for paper in userData.papers {
            if let block = paper.blocks.first(where: { $0.id == id }) {
                return (paper.id, block)
            }
        }
        return nil
    }

    /// The block of `work` that an intent changes: `picked`, while it is still there; else the
    /// only one not done yet, or the one Siri asks for among those.
    func blockToChange(
        _ picked: BlockEntity?, of work: WorkEntity, asking parameter: IntentParameter<BlockEntity?>
    ) async throws -> TimeBlock {
        guard let paper = userData.papers.first(where: { $0.id == work.id }) else { throw IntentFailure.notFound }
        if let picked, let block = paper.blocks.first(where: { $0.id == picked.id }) {
            return block
        }
        let open = paper.blocks.filter { !$0.isDone }.sorted { $0.start < $1.start }
        guard open.count > 1 else {
            guard let block = open.first else { throw IntentFailure.nothingLeft(work.title) }
            return block
        }
        let chosen = try await parameter.requestDisambiguation(
            among: open.map { BlockEntity($0, of: paper) }, dialog: "Which block?")
        guard let found = block(chosen.id), found.paperID == work.id else { throw IntentFailure.notFound }
        return found.block
    }
}
