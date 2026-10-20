#if DEBUG
import AppKit
import DrBarKit
import DrBarUI
import SwiftUI

/// Renders the main views to PNG files with the demo data, in light and dark appearance.
@MainActor
enum DebugSnapshots {
    static func render(into folder: URL) async {
        let store = AppStore.shared
        await store.prepareForDemo()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let paperID = store.userData.papers[0].id

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await snapshot(
                PopoverView(), width: PopoverView.width, appearance: appearance,
                to: folder.appending(path: "popover-\(suffix).png"))
            if let row = store.listedRows(since: store.axis.start).first(where: { $0.name == "CVPR" }) {
                await snapshot(
                    PopoverView(page: .detail(row.source)), width: PopoverView.width, appearance: appearance,
                    to: folder.appending(path: "popover-detail-\(suffix).png"))
            }

            store.plannerSelection = .overview
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 1000), appearance: appearance,
                to: folder.appending(path: "planner-overview-\(suffix).png"))
            store.plannerSelection = .conferences
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 720), appearance: appearance,
                to: folder.appending(path: "planner-conferences-\(suffix).png"))
            // As narrow as the window goes: the details give way to the list.
            await snapshot(
                PlannerWindow(), size: CGSize(width: 760, height: 600), appearance: appearance,
                to: folder.appending(path: "planner-conferences-narrow-\(suffix).png"))
            store.plannerSelection = .paper(paperID)
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 900), appearance: appearance,
                to: folder.appending(path: "planner-paper-\(suffix).png"))
            // All the way down to its deadlines and to-dos.
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 1640), appearance: appearance,
                to: folder.appending(path: "planner-paper-whole-\(suffix).png"))

            // The next deadline, a paper picked for the menu bar, one whose blocks overlap, and an item
            // that is only a deadline.
            let item = store.userData.papers.first { !$0.isPaper && $0.blocks.isEmpty }?.id ?? paperID
            let overlapping = store.userData.papers.first { $0.title == "RL Benchmark Suite" }?.id ?? paperID
            let subjects: [(AppSettings.MenuBarSubject?, String)] = [
                (nil, "next"), (.paper(paperID), "paper"), (.paper(overlapping), "overlap"), (.paper(item), "item"),
            ]
            for (subject, name) in subjects {
                store.userData.settings.menuBarSubject = subject
                for style in AppSettings.MenuBarStyle.allCases {
                    let glance = store.menuBarGlance(limit: style == .stack ? MenuBarLabel.stackCount : 1)
                    let menuBar = MenuBarLabel.image(glance, now: store.now, style: style)
                    await snapshot(
                        Image(nsImage: menuBar).padding(6).background(appearance == .aqua ? Color.white : Color.black)
                            .foregroundStyle(appearance == .aqua ? Color.black : Color.white),
                        width: nil, appearance: appearance,
                        to: folder.appending(path: "menubar-\(name)-\(style.rawValue)-\(suffix).png"))
                }
            }
            // Four ways it looks, side by side on the menu bar's own color, for the guide: the next
            // deadline, with its days, a picked paper, and the next two.
            let ways: [(AppSettings.MenuBarSubject?, AppSettings.MenuBarStyle)] = [
                (nil, .bar), (nil, .days), (.paper(paperID), .bar), (nil, .stack),
            ]
            var items: [NSImage] = []
            for (subject, style) in ways {
                store.userData.settings.menuBarSubject = subject
                let glance = store.menuBarGlance(limit: style == .stack ? MenuBarLabel.stackCount : 1)
                items.append(MenuBarLabel.image(glance, now: store.now, style: style))
            }
            await snapshot(
                HStack(spacing: 22) {
                    ForEach(items.indices, id: \.self) { Image(nsImage: items[$0]) }
                }
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(appearance == .aqua ? Color(white: 0.94) : Color(white: 0.16)),
                width: nil, appearance: appearance, to: folder.appending(path: "menubar-strip-\(suffix).png"))
            store.userData.settings.menuBarSubject = nil
        }

        let settings: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettings())), ("reminders", AnyView(NotificationSettings())),
            ("email", AnyView(EmailSettings())), ("data", AnyView(DataSettings())),
            ("about", AnyView(AboutView())),
        ]
        for (name, view) in settings {
            await snapshot(
                view.frame(width: 520), appearance: .aqua, to: folder.appending(path: "settings-\(name).png"))
        }
        if let paper = store.userData.papers.first {
            await snapshot(
                SendProgressSheet(paperID: paper.id, onSent: { _ in }), appearance: .aqua,
                to: folder.appending(path: "send-sheet.png"))
            // As the last update was, with the other work the supervisors may hear about.
            if !paper.threads.isEmpty {
                store.userData.papers[0].threads[0].includesOtherWork = true
                await snapshot(
                    SendProgressSheet(paperID: paper.id, onSent: { _ in }), appearance: .aqua,
                    to: folder.appending(path: "send-sheet-other-work.png"))
                store.userData.papers[0] = paper
            }
        }
        if let paper = store.userData.papers.first(where: { $0.target == nil && !$0.deadlines.isEmpty }),
            let deadline = paper.deadlines.first
        {
            await snapshot(
                DeadlineEditor(paperID: paper.id, id: deadline.id) {}, appearance: .aqua,
                to: folder.appending(path: "custom-deadline.png"))
        }
        await snapshot(
            TargetBrowser(paperID: paperID, undoManager: nil), appearance: .aqua,
            to: folder.appending(path: "target-browser.png"))
        // The sidebar on its own: the window's sidebar itself does not draw off screen. Then with a
        // group's name being typed.
        await snapshot(
            PlannerSidebar().listStyle(.sidebar).frame(width: 240, height: 480), appearance: .aqua,
            to: folder.appending(path: "sidebar.png"))
        store.renamingGroup = store.userData.groups.first?.id
        await snapshot(
            PlannerSidebar().listStyle(.sidebar).frame(width: 240, height: 480), appearance: .aqua,
            to: folder.appending(path: "sidebar-naming.png"))
        store.renamingGroup = nil

        // Medium and small rows; the small ones dark too, for the website.
        for size in [AppSettings.RowSize.medium, .small] {
            store.userData.settings.rowSize = size
            await snapshot(
                PopoverView(), width: PopoverView.width, appearance: .aqua,
                to: folder.appending(path: "popover-rows-\(size.rawValue)-light.png"))
            if size == .small {
                await snapshot(
                    PopoverView(), width: PopoverView.width, appearance: .darkAqua,
                    to: folder.appending(path: "popover-rows-small-dark.png"))
            }
            store.plannerSelection = .overview
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 760), appearance: .aqua,
                to: folder.appending(path: "planner-overview-rows-\(size.rawValue)-light.png"))
        }
        store.userData.settings.rowSize = .large

        store.axisRange = .sixMonths
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-6-months-light.png"))
        // Close enough for the days to be named, and the week itself.
        store.axisRange = .month
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-month-light.png"))
        store.axisRange = .week
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-week-light.png"))
        store.plannerSelection = .paper(paperID)
        await snapshot(
            PlannerWindow(), size: CGSize(width: 1100, height: 900), appearance: .darkAqua,
            to: folder.appending(path: "planner-paper-week-dark.png"))
        store.axisRange = .threeMonths

        // Swiped back six weeks: what has passed, and the way back to today.
        store.popoverPosition = AxisPosition(shift: -42)
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-earlier-light.png"))
        // Zoomed in to a few weeks, and out to more than a year.
        store.popoverPosition = AxisPosition(zoom: 5)
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-closer-light.png"))
        store.popoverPosition = AxisPosition(zoom: 0.25)
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-further-light.png"))
        store.popoverPosition = AxisPosition()

        // Labelled with the days from today, as chosen in Settings, also close in and far out.
        store.userData.settings.axisLabels = .days
        for (name, zoom) in [("", 1.0), ("-closer", 5), ("-further", 0.25)] {
            store.popoverPosition = AxisPosition(zoom: zoom)
            await snapshot(
                PopoverView(), width: PopoverView.width, appearance: .aqua,
                to: folder.appending(path: "popover-days\(name)-light.png"))
        }
        store.popoverPosition = AxisPosition()
        store.plannerSelection = .paper(paperID)
        await snapshot(
            PlannerWindow(), size: CGSize(width: 1100, height: 900), appearance: .aqua,
            to: folder.appending(path: "planner-paper-days-light.png"))
        // With both the dates and the days; close in, dark too, for the website.
        store.userData.settings.axisLabels = .both
        for (name, zoom) in [("", 1.0), ("-closer", 5)] {
            store.popoverPosition = AxisPosition(zoom: zoom)
            await snapshot(
                PopoverView(), width: PopoverView.width, appearance: .aqua,
                to: folder.appending(path: "popover-both\(name)-light.png"))
        }
        // The window went back to its range as it closed.
        store.popoverPosition = AxisPosition(zoom: 5)
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .darkAqua,
            to: folder.appending(path: "popover-both-closer-dark.png"))
        store.popoverPosition = AxisPosition()
        await snapshot(
            PlannerWindow(), size: CGSize(width: 1100, height: 900), appearance: .aqua,
            to: folder.appending(path: "planner-paper-both-light.png"))
        store.userData.settings.axisLabels = .dates

        // The Archive and Recently Deleted.
        for (selection, name) in [(PlannerSelection.archive, "archive"), (.recentlyDeleted, "recently-deleted")] {
            store.plannerSelection = selection
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 600), appearance: .aqua,
                to: folder.appending(path: "planner-\(name)-light.png"))
        }

        // Hover cards, as when the pointer has rested: on a paper's name, on a block someone works
        // on, on a block whose name is cut short, on a milestone and on a conference; and on a
        // block whose bar says it all, which has none.
        let first = store.userData.papers[0]
        let today = Day(store.now)
        store.plannerSelection = .overview
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await snapshot(
                PlannerWindow().environment(\.hoverCardPreview, first.id.uuidString),
                size: CGSize(width: 1100, height: 700), appearance: appearance,
                to: folder.appending(path: "card-paper-\(suffix).png"))
        }
        if let plain = first.blocks.first(where: { $0.people.isEmpty && !$0.isDone && $0.end >= today }) {
            await snapshot(
                PlannerWindow().environment(\.hoverCardPreview, plain.id.uuidString),
                size: CGSize(width: 1100, height: 700), appearance: .aqua,
                to: folder.appending(path: "card-none-light.png"))
        }
        if let block = first.blocks.first(where: { !$0.people.isEmpty }) {
            store.plannerSelection = .paper(first.id)
            await snapshot(
                PlannerWindow().environment(\.hoverCardPreview, block.id.uuidString),
                size: CGSize(width: 1100, height: 700), appearance: .darkAqua,
                to: folder.appending(path: "card-block-dark.png"))
        }
        if let cut = store.userData.papers.flatMap(\.blocks).first(where: { $0.displayName == "Research proposal" }) {
            await snapshot(
                PopoverView().environment(\.hoverCardPreview, cut.id.uuidString), width: PopoverView.width,
                appearance: .aqua, to: folder.appending(path: "card-block-name-light.png"))
        }
        if let milestone = first.milestones.first(where: { !$0.isDone }) {
            await snapshot(
                PopoverView().environment(\.hoverCardPreview, milestone.id.uuidString), width: PopoverView.width,
                appearance: .aqua, to: folder.appending(path: "card-milestone-light.png"))
        }
        if let row = store.listedRows(since: store.axis.start).first(where: { $0.name == "CVPR" }) {
            await snapshot(
                PopoverView().environment(\.hoverCardPreview, row.id), width: PopoverView.width, appearance: .aqua,
                to: folder.appending(path: "card-conference-light.png"))
        }
        // The flag on a paper's Deadlines row.
        if let flag = store.overview(for: first).flag {
            store.plannerSelection = .paper(first.id)
            await snapshot(
                PlannerWindow().environment(\.hoverCardPreview, "deadline|" + flag.id),
                size: CGSize(width: 1100, height: 700), appearance: .aqua,
                to: folder.appending(path: "card-deadline-light.png"))
        }

        // An item of a group: planned as a paper is, without stages or progress emails.
        if let item = store.userData.papers.first(where: { !$0.isPaper }) {
            store.plannerSelection = .paper(item.id)
            await snapshot(
                PlannerWindow(), size: CGSize(width: 1100, height: 800), appearance: .aqua,
                to: folder.appending(path: "planner-item-light.png"))
        }

        let paper = store.userData.papers[0]
        for language in MailLanguage.allCases {
            var group = store.userData.mail.groups[0]
            group.language = language
            let content = TimelineImage.content(
                for: paper, overview: store.overview(for: paper), group: group, people: store.userData.people,
                now: store.now)
            if let png = TimelineImage.png(content) {
                try? png.write(to: folder.appending(path: "email-image-\(language.rawValue).png"))
            }
            let others = store.userData.work(
                visibleTo: group.recipients, besides: paper.id, catalog: store.catalog, now: store.now)
            let withOthers = TimelineImage.content(
                for: paper, overview: store.overview(for: paper), group: group, people: store.userData.people,
                otherWork: others, now: store.now)
            if let png = TimelineImage.png(withOthers) {
                try? png.write(to: folder.appending(path: "email-image-other-work-\(language.rawValue).png"))
            }
            let otherWork = ProgressSummary.otherWork(
                others, language: language, hidesBufferBlocks: group.hidesBufferBlocks, now: store.now)
            let headline = ProgressSummary.headline(
                paper: paper, status: content.status, recipients: Set(group.people.map(\.id)),
                lastUpdate: paper.thread(for: group.id)?.lastSentAt, language: language, hidesBufferBlocks: true,
                now: store.now)
            let summary = ProgressSummary.text(
                paper: paper, deadlines: store.overview(for: paper).deadlines, language: language,
                hidesBufferBlocks: true, people: store.userData.people, now: store.now)
            try? ([headline, summary, otherWork ?? ""].joined(separator: "\n\n")).write(
                to: folder.appending(path: "email-summary-\(language.rawValue).txt"), atomically: true, encoding: .utf8)
        }

        // Siri's actions, which change the data, then what a new user sees.
        await IntentCheck.run(into: folder.appending(path: "intents.txt"))
        store.userData = UserData()
        await snapshot(
            PopoverView(), width: PopoverView.width, appearance: .aqua,
            to: folder.appending(path: "popover-welcome-light.png"))
    }

    /// Hosts the view in an offscreen window and draws it into a bitmap.
    /// What views remember for themselves, such as the order of the conferences, in a domain of its
    /// own that starts empty, so that snapshots show what a first launch shows.
    private static let storage: UserDefaults = {
        let name = "DrBarSnapshots"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }()

    private static func snapshot<V: View>(
        _ view: V, width: CGFloat? = nil, size: CGSize? = nil, appearance: NSAppearance.Name, to url: URL
    ) async {
        // Drawn at rest: bars grown in, pages in place.
        let root =
            view
            .modifier(TimelineEnvironment())
            .environment(AppStore.shared)
            .defaultAppStorage(storage)
            .background(Color(nsColor: .windowBackgroundColor))
            .transaction { $0.animation = nil }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        var frame = CGRect(origin: .zero, size: size ?? host.fittingSize)
        if let width {
            host.frame = CGRect(x: 0, y: 0, width: width, height: 100)
            frame.size = CGSize(width: width, height: host.fittingSize.height)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.frame = frame
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(600))
        if let width {
            // Views that measure themselves (FittingScrollView) settle after the first layout.
            frame.size = CGSize(width: width, height: host.fittingSize.height)
            window.setContentSize(frame.size)
            host.frame = frame
            try? await Task.sleep(for: .milliseconds(400))
        }
        // A screenshot should not show a text field that happens to have the focus.
        window.makeFirstResponder(nil)
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            // In sRGB, as the web and other screens take it, not in the colors of this screen.
            try? rep.converting(to: .sRGB, renderingIntent: .default)?
                .representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
        // The view's disappearance settles before the next snapshot sets up its state: the
        // popover goes back to today when it closes.
        window.contentView = nil
        try? await Task.sleep(for: .milliseconds(100))
    }
}
#endif
