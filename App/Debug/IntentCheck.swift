#if DEBUG
import AppIntents
import Foundation
import DrBarKit
import DrBarUI

/// Runs each of Siri's actions on the demo data, as Siri would with everything said, and writes
/// what it answered and whether it did what it said, so that a snapshot run shows they still work.
@MainActor
enum IntentCheck {
    static func run(into url: URL) async {
        let store = AppStore.shared
        let today = Day(store.now)
        var lines: [String] = []
        func check(_ name: String, _ body: () async throws -> (Any, Bool)) async {
            do {
                let (result, isDone) = try await body()
                lines.append("\(isDone ? "✓" : "✗") \(name): \(spoken(result) ?? "(no answer)")")
            } catch {
                lines.append("✗ \(name): \(said(error))")
            }
        }
        func refuses(_ name: String, _ body: () async throws -> Any) async {
            do {
                _ = try await body()
                lines.append("✗ \(name): went ahead")
            } catch {
                lines.append("✓ \(name): \(said(error))")
            }
        }
        guard let reviews = GroupEntity.all.first(where: { $0.name == "Reviews" }),
            let paper = store.userData.papers.first
        else {
            try? "✗ The demo data has no Reviews or no paper.".write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let work = WorkEntity(paper, in: store)

        lines.append("Groups: " + GroupEntity.all.map(\.name).joined(separator: ", "))
        let found = try? await WorkQuery().entities(matching: "video")
        lines.append("Papers and items matching “video”: " + (found ?? []).map(\.title).joined(separator: ", "))

        var added: WorkEntity?
        await check("Add to Reviews") {
            let intent = AddWorkIntent()
            intent.title = "TMLR review"
            intent.due = today.adding(14).startDate()
            intent.group = reviews
            let result = try await intent.perform()
            let item = store.userData.papers.first { $0.title == "TMLR review" }
            added = item.map { WorkEntity($0, in: store) }
            let isDue = item?.deadlines.contains { Day($0.date) == today.adding(14) } == true
            return (result, item?.groupID == reviews.groupID && isDue)
        }
        await refuses("Add with no title") {
            let intent = AddWorkIntent()
            intent.title = "  "
            intent.due = today.startDate()
            intent.group = reviews
            return try await intent.perform()
        }
        if let added {
            await check("Add a deadline") {
                let intent = AddDeadlineIntent()
                intent.work = added
                intent.day = today.adding(10).startDate()
                intent.name = "Report"
                let result = try await intent.perform()
                let item = store.userData.papers.first { $0.id == added.id }
                let isAdded = item?.deadlines.contains { $0.title == "Report" && Day($0.date) == today.adding(10) }
                return (result, isAdded == true)
            }
        }

        var block: TimeBlock?
        await check("Add a block") {
            let intent = AddBlockIntent()
            intent.work = work
            intent.kind = .writing
            intent.start = today.adding(2).startDate()
            intent.days = 5
            let before = Set(paper.blocks.map(\.id))
            let result = try await intent.perform()
            block = store.userData.papers.first { $0.id == paper.id }?.blocks.first { !before.contains($0.id) }
            return (result, block?.kind == .writing && block?.start == today.adding(2) && block?.end == today.adding(6))
        }
        if let first = block {
            // As Siri has it after each change.
            let entity = {
                BlockEntity(store.block(first.id)!.block, of: store.userData.papers.first { $0.id == paper.id }!)
            }
            await check("Move a block") {
                let intent = MoveBlockIntent()
                intent.work = work
                intent.block = entity()
                intent.start = today.adding(4).startDate()
                let result = try await intent.perform()
                let moved = store.block(first.id)?.block
                return (result, moved?.start == today.adding(4) && moved?.end == today.adding(8))
            }
            await check("Change when a block ends") {
                let intent = EndBlockIntent()
                intent.work = work
                intent.block = entity()
                intent.end = today.adding(12).startDate()
                let result = try await intent.perform()
                return (result, store.block(first.id)?.block.end == today.adding(12))
            }
            await check("Mark a block as done") {
                let intent = MarkBlockDoneIntent()
                intent.work = work
                intent.block = entity()
                let result = try await intent.perform()
                return (result, store.block(first.id)?.block.isDone == true)
            }
        }
        if let added {
            await refuses("Mark a block of work without blocks as done") {
                let intent = MarkBlockDoneIntent()
                intent.work = added
                return try await intent.perform()
            }
        }
        await check("What’s next") {
            let result = try await NextDeadlineIntent().perform()
            return (result, store.upcomingDeadlines(limit: 1).first != nil)
        }
        // Opening a paper is left out, as it would bring the planner to the front; Siri finds it by id.
        let opened = try? await WorkQuery().entities(for: [paper.id])
        lines.append("\(opened?.first?.id == paper.id ? "✓" : "✗") Open a paper: finds “\(work.title)”")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// What Siri says when an action cannot go ahead, or that it asks again.
    private static func said(_ error: Error) -> String {
        if error is AppIntentError {
            return "(asks again)"
        }
        if let error = error as? any CustomLocalizedStringResourceConvertible {
            return String(localized: error.localizedStringResource)
        }
        return error.localizedDescription
    }

    /// What an action's result says, as Siri reads it out: its dialog, which the system keeps as a
    /// string of its own, localized when it is read.
    private static func spoken(_ value: Any, inDialog: Bool = false) -> String? {
        let localize = NSSelectorFromString("localizedStringForLocaleIdentifier:")
        if inDialog, let object = value as? NSObject, object.responds(to: localize) {
            return object.perform(localize, with: Locale.current.identifier)?.takeUnretainedValue() as? String
        }
        for child in Mirror(reflecting: value).children {
            if let text = spoken(child.value, inDialog: inDialog || child.label == "dialog") {
                return text
            }
        }
        return nil
    }
}
#endif
