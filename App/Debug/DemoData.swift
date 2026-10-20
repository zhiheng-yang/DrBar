#if DEBUG
import DrBarKit
import SwiftUI

/// Sample data for screenshots, previews and trying the app out, in debug builds only.
///
/// `-DrBarDemo YES` runs the app on this data in a temporary folder, so real data is never
/// touched. `-DrBarSnapshots <folder>` also renders the main views to PNG files and quits, and
/// `-DrBarRecord <folder>` draws their motion frame by frame (`DebugRecording`). Xcode previews
/// always use it.
enum DemoData {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DrBarDemo") || rendersOnly
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static var snapshotFolder: URL? {
        folder(forKey: "DrBarSnapshots")
    }

    static var recordingFolder: URL? {
        folder(forKey: "DrBarRecord")
    }

    /// Whether the app only draws itself into files and quits.
    static var rendersOnly: Bool {
        snapshotFolder != nil || recordingFolder != nil
    }

    private static func folder(forKey key: String) -> URL? {
        UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// A folder of its own. Snapshots start from an empty one, so that they show the ccfddl data
    /// bundled with the app, the same every time.
    static var files: AppFiles {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: rendersOnly ? "DrBarSnapshots" : "DrBarDemo", directoryHint: .isDirectory)
        if rendersOnly {
            try? FileManager.default.removeItem(at: directory)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppFiles(directory: directory)
    }

    static func userData(now: Date = Date()) -> UserData {
        let today = Day(now)
        let jane = Person(name: "Prof. Jane Doe", email: "jane.doe@example.org")
        let sam = Person(name: "Sam Lee", email: "sam.lee@example.org")
        let mia = Person(name: "Mia Chen", email: "mia.chen@example.org")
        func block(
            _ kind: TimeBlock.Kind, _ name: String = "", start: Int, end: Int, done: Bool = false,
            with people: [Person] = []
        ) -> TimeBlock {
            TimeBlock(
                kind: kind, customName: name, start: today.adding(start), end: today.adding(end), isDone: done,
                people: people.map(\.id))
        }
        func endOfDay(in days: Double, zone: String = "AoE") -> Date {
            Calendar.gregorian(in: DeadlineTimeZone.custom(zone) ?? .current)
                .lastMinute(of: now.addingTimeInterval(days * 86_400))
        }
        // The last day of the plans of the two conference papers: the day before their paper
        // deadlines, as the bundled ccfddl data gives them, so that the plans fit on any day.
        let ccfddl = Calendar.gregorian(in: DeadlineTimeZone.ccf("UTC-12")!)
        func lastDay(before month: Int, _ day: Int) -> Int {
            let deadline = ccfddl.date(from: DateComponents(year: 2026, month: month, day: day, hour: 23, minute: 59))!
            return today.days(to: Day(deadline)) - 1
        }
        let cvpr = lastDay(before: 11, 16)
        let icaps = lastDay(before: 12, 14)
        let local = TimeZone.current.identifier
        let workshop = CustomDeadline(
            title: "NeurIPS Workshop on Efficient Models", date: endOfDay(in: 19), timeZone: "AoE",
            link: "https://example.org/workshop")
        let applications = ItemGroup(name: "Applications", symbol: "briefcase")
        let fellowship = CustomDeadline(title: "", date: endOfDay(in: 27), timeZone: "AoE")
        let visiting = CustomDeadline(title: "", date: endOfDay(in: 58), timeZone: "AoE")
        // Reviews that are only due on a day, two of them on the same one, each taken on some days ago,
        // which their countdowns in the menu bar start from.
        let reviews = ItemGroup(name: "Reviews", symbol: "magnifyingglass")
        let review = { (title: String, days: Double, takenOn: Double) in
            let due = CustomDeadline(title: "", date: endOfDay(in: days), timeZone: "AoE")
            return Paper(
                title: title, deadlines: [due], mainDeadline: due.id, groupID: reviews.id,
                createdAt: now.addingTimeInterval(-takenOn * 86_400))
        }
        let papers = [
            Paper(
                title: "Efficient Video Diffusion", target: Paper.Target(series: "AI/cvpr", year: 2027),
                // A week after CVPR 2027's paper deadline, as its supplementary material usually is.
                deadlines: [
                    CustomDeadline(
                        title: "Supplementary material",
                        date: Calendar.gregorian(in: DeadlineTimeZone.ccf("UTC-12")!)
                            .date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 59))!,
                        timeZone: "UTC-12")
                ],
                stage: .writing,
                blocks: [
                    block(.experiments, start: -16, end: -3, done: true),
                    block(.writing, start: -2, end: cvpr - 18),
                    block(.review, start: cvpr - 17, end: cvpr - 10, with: [jane]),
                    // A second round of writing, after the internal review.
                    block(.writing, start: cvpr - 9, end: cvpr - 4, with: [sam]),
                    block(.buffer, start: cvpr - 3, end: cvpr),
                ],
                milestones: [
                    Milestone(title: "Results frozen", day: today.adding(-4), isDone: true),
                    Milestone(title: "Full draft to Jane", day: today.adding(cvpr - 21)),
                    Milestone(title: "Internal deadline", day: today.adding(cvpr - 4)),
                ],
                todos: [
                    TodoItem(title: "Rerun the baselines with five seeds", isDone: true),
                    TodoItem(title: "Add the ablation table"),
                    TodoItem(title: "Ask Jane about the related work section"),
                ],
                threads: [
                    MailThread(
                        groupID: MailSettings.defaultGroups[0].id, subject: "Progress: Efficient Video Diffusion",
                        startedAt: now.addingTimeInterval(-30 * 86_400), lastSentAt: now.addingTimeInterval(-3 * 86_400)
                    )
                ]),
            Paper(
                title: "RL Benchmark Suite", target: Paper.Target(series: "AI/icaps", year: 2027),
                stage: .experiments,
                blocks: [
                    block(.custom, "Baselines", start: -10, end: -4),
                    block(.experiments, start: -3, end: 22, with: [mia]),
                    // Writing starts while the last experiments run.
                    block(.writing, start: 17, end: icaps - 15, with: [sam, mia]),
                    block(.review, start: icaps - 14, end: icaps - 5),
                ],
                todos: [TodoItem(title: "Rerun PPO with five seeds")], visibleTo: [jane.id]),
            Paper(
                title: "Sparse Attention Probes", deadlines: [workshop], mainDeadline: workshop.id, stage: .writing,
                blocks: [
                    block(.experiments, start: -9, end: -1, done: true),
                    block(.writing, start: 0, end: 13),
                    block(.review, start: 14, end: 18),
                ]),
            Paper(
                title: "Scaling Laws for Theorem Provers", target: Paper.Target(series: "AI/colt", year: 2027)),
            Paper(
                title: "Doctoral Fellowship",
                deadlines: [
                    CustomDeadline(
                        title: "Letters of recommendation", date: endOfDay(in: 13, zone: local), timeZone: local,
                        isDone: true),
                    fellowship,
                    CustomDeadline(title: "Interview", date: endOfDay(in: 75, zone: local), timeZone: local),
                ],
                mainDeadline: fellowship.id,
                blocks: [
                    block(.custom, "Research proposal", start: 0, end: 14),
                    // The documents are gathered while the proposal is written.
                    block(.custom, "CV and transcripts", start: 6, end: 11),
                    block(.review, start: 15, end: 22, with: [jane]),
                    block(.buffer, start: 23, end: 27),
                ],
                milestones: [Milestone(title: "Ask Jane for a letter", day: today.adding(3))],
                visibleTo: [jane.id], groupID: applications.id),
            Paper(
                title: "Visiting Researcher Program", deadlines: [visiting], mainDeadline: visiting.id,
                groupID: applications.id, createdAt: now.addingTimeInterval(-20 * 86_400)),
            review("ICLR 2027 reviews", 12, 16), review("JMLR review", 12, 30), review("TPAMI review", 33, 7),
        ]
        var settings = AppSettings()
        settings.notificationsEnabled = false
        var mail = MailSettings(signature: "Alex")
        mail.groups[0].people = [jane]
        mail.groups[1].people = [sam, mia]
        // Put away after its decision, and an item deleted a few days ago.
        let archived = Paper(
            title: "Graph Transformers for Code", target: Paper.Target(series: "AI/iclr", year: 2026),
            stage: .decided,
            blocks: [
                block(.experiments, start: -150, end: -110, done: true),
                block(.writing, start: -109, end: -90, done: true),
            ],
            archivedAt: now.addingTimeInterval(-20 * 86_400))
        let deleted = DeletedPaper(
            paper: Paper(title: "Travel Grant", groupID: applications.id),
            deletedAt: now.addingTimeInterval(-3 * 86_400))
        // A block of the first paper deleted an hour ago, and a to-do of the second yesterday.
        let deletedParts = [
            DeletedPart(
                .block(block(.custom, "Ablations", start: 4, end: 9)), paperID: papers[0].id, index: 2,
                deletedAt: now.addingTimeInterval(-3600)),
            DeletedPart(
                .todo(TodoItem(title: "Plot the learning curves")), paperID: papers[1].id, index: 1,
                deletedAt: now.addingTimeInterval(-86_400)),
        ]
        return UserData(
            favoriteSeries: ["AI/alt", "AI/cvpr", "AI/icaps", "AI/ijcai", "AI/colt"], papers: papers,
            groups: [applications, reviews], archive: [archived], recentlyDeleted: [deleted],
            deletedParts: deletedParts,
            mail: mail, settings: settings)
    }
}

/// A view on the sample data with the bundled conference data loaded, for `#Preview`.
struct DemoPreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(AppStore.shared)
            .task { await AppStore.shared.prepareForDemo() }
    }
}
#endif
