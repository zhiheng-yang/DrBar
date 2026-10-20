import AppIntents
import DrBarKit
import DrBarUI

/// Adds a paper, or an item to one of the groups, due on a day: "Add to Reviews in DrBar".
struct AddWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Paper or Item"
    static let description = IntentDescription("Adds a paper, or an item to one of your groups, due on a day.")

    @Parameter(title: "Title", requestValueDialog: "What is it called?")
    var title: String

    @Parameter(title: "Due", kind: .date, requestValueDialog: "When is it due?")
    var due: Date

    @Parameter(title: "Group", requestValueDialog: "Which group is it in?")
    var group: GroupEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title) to \(\.$group), due \(\.$due)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WorkEntity> & ProvidesDialog {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw $title.needsValueError("What is it called?") }
        let store = AppStore.shared
        guard let id = store.addWork(title: name, in: group.groupID, dueOn: Day(due)),
            let paper = store.userData.papers.first(where: { $0.id == id })
        else { throw IntentFailure.notFound }
        let work = WorkEntity(paper, in: store)
        return .result(value: work, dialog: "Added “\(work.title)” to \(work.group), due \(Self.day(due)).")
    }

    /// "Sunday, November 1".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// Adds a deadline of its own to a paper or an item, at 23:59 on a day.
struct AddDeadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Deadline"
    static let description = IntentDescription("Adds a deadline to a paper or an item, at 23:59 on a day.")

    @Parameter(title: "Paper or Item", requestValueDialog: "Which paper or item?")
    var work: WorkEntity

    @Parameter(title: "Day", kind: .date, requestValueDialog: "On which day?")
    var day: Date

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add a deadline on \(\.$day) to \(\.$work)") {
            \.$name
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard AppStore.shared.addDeadline(to: work.id, on: Day(day), title: title, undoManager: nil) != nil else {
            throw IntentFailure.notFound
        }
        return .result(dialog: "Added a deadline to “\(work.title)” on \(AddWorkIntent.day(day)).")
    }
}

/// Opens a paper or an item in the planner.
struct OpenWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Paper or Item"
    static let description = IntentDescription("Opens a paper or an item in the planner.")
    static let openAppWhenRun = true

    @Parameter(title: "Paper or Item", requestValueDialog: "Which paper or item?")
    var work: WorkEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$work)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared.open(.paper(work.id))
        return .result()
    }
}

/// Tells which deadline comes next, of the work and the starred conferences, and how far it is.
struct NextDeadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Deadline"
    static let description = IntentDescription(
        "Tells which deadline comes next, of your work and the conferences you follow, and how long is left.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        await store.waitForCatalog()
        guard let next = store.upcomingDeadlines(limit: 1).first else {
            return .result(dialog: "Nothing is due.")
        }
        let when = DeadlineText.localDateTime(next.date)
        let left = CountdownText.spoken(next.date.timeIntervalSinceNow)
        return .result(dialog: "\(next.title), \(next.deadline.name): \(when), \(left).")
    }
}
