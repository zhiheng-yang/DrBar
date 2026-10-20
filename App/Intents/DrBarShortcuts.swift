import AppIntents
import DrBarKit

/// What Siri, Spotlight and the Shortcuts app offer without any setting up, with the phrases that
/// start each. Siri asks for what a phrase leaves out.
struct DrBarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddWorkIntent(),
            phrases: ["Add to \(\.$group) in \(.applicationName)", "Add a new item in \(.applicationName)"],
            shortTitle: "Add a Paper or Item", systemImageName: "plus.circle")
        AppShortcut(
            intent: AddDeadlineIntent(),
            phrases: ["Add a deadline to \(\.$work) in \(.applicationName)", "Add a deadline in \(.applicationName)"],
            shortTitle: "Add a Deadline", systemImageName: "flag")
        AppShortcut(
            intent: AddBlockIntent(),
            phrases: [
                "Add a block to \(\.$work) in \(.applicationName)",
                "Plan \(\.$kind) in \(.applicationName)",
                "Add a block in \(.applicationName)",
            ],
            shortTitle: "Add a Block", systemImageName: "rectangle.badge.plus")
        AppShortcut(
            intent: MoveBlockIntent(),
            phrases: [
                "Move a block of \(\.$work) in \(.applicationName)",
                "Postpone a block of \(\.$work) in \(.applicationName)",
                "Bring forward a block of \(\.$work) in \(.applicationName)",
                "Move a block in \(.applicationName)",
            ],
            shortTitle: "Move a Block", systemImageName: "arrow.left.and.right")
        AppShortcut(
            intent: EndBlockIntent(),
            phrases: [
                "Extend a block of \(\.$work) in \(.applicationName)",
                "Shorten a block of \(\.$work) in \(.applicationName)",
                "Change when a block of \(\.$work) ends in \(.applicationName)",
                "Extend a block in \(.applicationName)",
            ],
            shortTitle: "Change When a Block Ends", systemImageName: "arrow.right.to.line")
        AppShortcut(
            intent: MarkBlockDoneIntent(),
            phrases: [
                "Mark a block of \(\.$work) as done in \(.applicationName)",
                "Check off a block of \(\.$work) in \(.applicationName)",
                "Mark a block as done in \(.applicationName)",
            ],
            shortTitle: "Mark a Block as Done", systemImageName: "checkmark.circle")
        AppShortcut(
            intent: NextDeadlineIntent(),
            phrases: ["What’s next in \(.applicationName)", "Next deadline in \(.applicationName)"],
            shortTitle: "Next Deadline", systemImageName: "graduationcap")
        AppShortcut(
            intent: OpenWorkIntent(), phrases: ["Open \(\.$work) in \(.applicationName)"],
            shortTitle: "Open a Paper or Item", systemImageName: "macwindow")
    }

    /// Forgets what the system has learned from the intents run, as Remove All Data does.
    static func forgetDonations() async {
        let intents: [any AppIntent.Type] = [
            AddWorkIntent.self, AddDeadlineIntent.self, AddBlockIntent.self, MoveBlockIntent.self, EndBlockIntent.self,
            MarkBlockDoneIntent.self, NextDeadlineIntent.self, OpenWorkIntent.self,
        ]
        for intent in intents {
            _ = try? await IntentDonationManager.shared.deleteDonations(matching: .intentType(intent))
        }
    }
}

extension AppStore {
    /// Lets Siri know the names it can hear in the phrases, the papers', items' and groups', when
    /// they have changed.
    func refreshShortcutNames() {
        #if DEBUG
        if DemoData.isEnabled { return }
        #endif
        let names = userData.papers.map { "\($0.id) \($0.title)" } + userData.groups.map { "\($0.id) \($0.name)" }
        guard names != shortcutNames else { return }
        shortcutNames = names
        DrBarShortcuts.updateAppShortcutParameters()
    }
}
