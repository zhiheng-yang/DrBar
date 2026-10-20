import Foundation

/// Everything the user maintains, stored in `user.json`.
///
/// Files from every released version must keep decoding, so every field has a default and is
/// decoded leniently; a field added later must never be required.
public struct UserData: Codable, Hashable, Sendable {
    /// Bumped only for a change that needs an explicit migration.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// Starred conference series (`AI/cvpr`). Stars apply to the series, so next year's edition is
    /// followed as soon as ccfddl lists it.
    public var favoriteSeries: Set<String>
    /// The papers and the items of the other groups, each group's in its own order.
    public var papers: [Paper]
    /// The groups besides the papers, in the order of the sidebar.
    public var groups: [ItemGroup]
    /// Where the papers come among the groups: how many groups are above them.
    public var papersPosition: Int
    /// Papers and items put away, with all they had, out of the groups and the timelines.
    public var archive: [Paper]
    /// Papers and items deleted in the last thirty days, which can still be recovered.
    public var recentlyDeleted: [DeletedPaper]
    /// Blocks, milestones, deadlines and to-dos deleted from them in the last thirty days.
    public var deletedParts: [DeletedPart]
    /// The deadlines of the list of earlier builds that belong to no paper yet, until
    /// `moveListedDeadlines` gives them to papers and items.
    public var listedDeadlines: [CustomDeadline]
    public var mail: MailSettings
    public var settings: AppSettings
    /// The raw deadline text last seen for each followed deadline (`DeadlineItem.id`), used to
    /// notice when ccfddl changes a date.
    public var lastSeen: [String: String]

    public init(
        favoriteSeries: Set<String> = [], papers: [Paper] = [], groups: [ItemGroup] = [], papersPosition: Int = 0,
        archive: [Paper] = [], recentlyDeleted: [DeletedPaper] = [], deletedParts: [DeletedPart] = [],
        listedDeadlines: [CustomDeadline] = [], mail: MailSettings = MailSettings(),
        settings: AppSettings = AppSettings(), lastSeen: [String: String] = [:]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.favoriteSeries = favoriteSeries
        self.papers = papers
        self.groups = groups
        self.papersPosition = papersPosition
        self.archive = archive
        self.recentlyDeleted = recentlyDeleted
        self.deletedParts = deletedParts
        self.listedDeadlines = listedDeadlines
        self.mail = mail
        self.settings = settings
        self.lastSeen = lastSeen
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, favoriteSeries, papers, groups, papersPosition, archive, recentlyDeleted, deletedParts,
            mail, settings, lastSeen
        /// The deadlines entered by hand, which earlier builds kept in one list.
        case customDeadlines
    }

    /// Fields of the first builds that are read, never written.
    private enum LegacyKeys: String, CodingKey {
        case supervisor
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        formatVersion = c(.formatVersion, default: Self.currentFormatVersion)
        favoriteSeries = Set(c(.favoriteSeries, default: [String]()))
        // Each paper and item once, wherever it is.
        var once = OnceByID(\Paper.id, report: c.report)
        papers = once.pass(c.list(.papers))
        groups = c.list(.groups, once: \.id)
        papersPosition = c(.papersPosition, default: 0)
        archive = once.pass(c.list(.archive))
        recentlyDeleted = (c.list(.recentlyDeleted) as [DeletedPaper]).filter { once.pass($0.paper) != nil }
        // The items of a group that could not be read join the papers, as when their group is gone.
        let known = Set(groups.map(\.id))
        for index in papers.indices where papers[index].groupID.map({ !known.contains($0) }) ?? false {
            papers[index].groupID = nil
        }
        for index in archive.indices where archive[index].groupID.map({ !known.contains($0) }) ?? false {
            archive[index].groupID = nil
        }
        deletedParts = c.list(.deletedParts)
        listedDeadlines = []
        let stored: [StoredDeadline] = c.list(.customDeadlines)
        let legacy = try LenientContainer(decoder, keyedBy: LegacyKeys.self)
        let supervisor: LegacySupervisor? = legacy(.supervisor, default: nil)
        mail = c(.mail, default: supervisor?.mailSettings ?? MailSettings())
        settings = c(.settings, default: AppSettings())
        lastSeen = c(.lastSeen, default: [:])
        // A paper's single thread from those builds was with the supervisor.
        if let supervisors = mail.groups.first(where: { $0.kind == .supervisors }) {
            papers = papers.map { $0.adoptingUnassignedThreads(into: supervisors.id) }
        }
        adopt(stored)
        dropOrphanedParts()
    }

    /// Earlier builds kept every deadline entered by hand in one list, each with the paper it
    /// belonged to. Each moves into its paper or item, wherever that is; one that a second paper
    /// aimed at too is copied into that one. Those of no paper wait in `listedDeadlines`.
    private mutating func adopt(_ stored: [StoredDeadline]) {
        var owned: [CustomDeadline] = []
        for entry in stored {
            var isGiven = false
            if let owner = entry.paperID {
                updateEveryPaper { paper in
                    guard paper.id == owner else { return }
                    if !paper.deadlines.contains(where: { $0.id == entry.deadline.id }) {
                        paper.deadlines.append(entry.deadline)
                    }
                    isGiven = true
                }
            }
            guard isGiven, let owner = entry.paperID else {
                listedDeadlines.append(entry.deadline)
                continue
            }
            owned.append(entry.deadline)
            if settings.menuBarSubject == .customDeadline(entry.deadline.id) {
                settings.menuBarSubject = .paper(owner)
            }
        }
        for deadline in owned {
            giveCopies(of: deadline)
        }
    }

    /// Gives each paper or item that aims at `deadline` without having it a copy of its own.
    mutating func giveCopies(of deadline: CustomDeadline) {
        updateEveryPaper { paper in
            guard paper.mainDeadline == deadline.id, !paper.deadlines.contains(where: { $0.id == deadline.id })
            else { return }
            var copy = deadline
            copy.id = UUID()
            paper.deadlines.append(copy)
            paper.mainDeadline = copy.id
        }
    }

    /// Every paper and item, also those in the Archive and in Recently Deleted.
    var everyPaper: [Paper] {
        papers + archive + recentlyDeleted.map(\.paper)
    }

    /// Changes every paper and item, also those in the Archive and in Recently Deleted.
    mutating func updateEveryPaper(_ update: (inout Paper) -> Void) {
        for index in papers.indices {
            update(&papers[index])
        }
        for index in archive.indices {
            update(&archive[index])
        }
        for index in recentlyDeleted.indices {
            update(&recentlyDeleted[index].paper)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(favoriteSeries.sorted(), forKey: .favoriteSeries)
        try c.encode(papers, forKey: .papers)
        try c.encode(groups, forKey: .groups)
        try c.encode(papersPosition, forKey: .papersPosition)
        try c.encode(archive, forKey: .archive)
        try c.encode(recentlyDeleted, forKey: .recentlyDeleted)
        try c.encode(deletedParts, forKey: .deletedParts)
        if !listedDeadlines.isEmpty {
            try c.encode(listedDeadlines, forKey: .customDeadlines)
        }
        try c.encode(mail, forKey: .mail)
        try c.encode(settings, forKey: .settings)
        try c.encode(lastSeen, forKey: .lastSeen)
    }
}

/// Preferences from the Settings window.
public struct AppSettings: Codable, Hashable, Sendable {
    public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
        /// What it shows and the next deadline's name, in the frame that goes round with the time.
        case bar
        /// The days left until each of the next two deadlines, in a frame each.
        case stack
        /// What it shows, the next deadline's name and the days left, in the frame.
        case days
        /// What it shows alone, in the frame.
        case iconOnly
    }

    /// Light or dark windows, or whichever the system uses.
    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system, light, dark
    }

    /// What the time axis is labelled with: the dates, how many days each line is from today, so
    /// that how far away something is can be read off without counting, or both.
    public enum AxisLabels: String, Codable, CaseIterable, Sendable {
        case dates, days, both

        public var showsDates: Bool {
            self != .days
        }

        public var showsDays: Bool {
            self != .dates
        }

        /// With the dates, the days or both shown; never neither, so the dates stay when both are
        /// turned off.
        public static func showing(dates: Bool, days: Bool) -> Self {
            dates && days ? .both : days ? .days : .dates
        }
    }

    /// How tall the rows of the timelines are: large, with a line under each name and the names of
    /// the blocks in their bars; medium; or small, a thin bar beside each name.
    public enum RowSize: String, Codable, CaseIterable, Sendable {
        case small, medium, large
    }

    /// What the menu bar item is about, when the user picks one thing for it.
    public enum MenuBarSubject: Codable, Hashable, Sendable {
        /// A paper or an item of another group: its plan, and the time left until its deadline.
        case paper(UUID)
        /// A conference series: its next deadline.
        case series(String)
        /// A custom deadline of the list of earlier builds; read, then shown by its paper or item
        /// (`UserData.moveListedDeadlines`).
        case customDeadline(UUID)
    }

    /// Default filters of the "All" conference list.
    public var categories: Set<String>
    public var ccfRanks: Set<String>
    /// Every rank, and N for the unranked, until the user leaves some out.
    public var coreRanks: Set<String>
    public var thcplRanks: Set<String>
    /// Off until the user turns reminders on; that is when permission is requested.
    public var notificationsEnabled: Bool
    /// Days before a deadline at which to remind.
    public var reminderDays: [Int]
    /// Remind at 9:00 on the last day of a block, and on the day of a milestone, that is not done.
    public var blockReminders: Bool
    /// Notify when ccfddl changes a followed date.
    public var dateChangeAlerts: Bool
    public var menuBarStyle: MenuBarStyle
    /// `nil` shows the next deadline of everything followed.
    public var menuBarSubject: MenuBarSubject?
    /// The time axis's range: a week, or 1, 3 or 6 months.
    public var axisRange: AxisRange
    public var axisLabels: AxisLabels
    public var rowSize: RowSize
    public var appearance: Appearance

    public static let reminderDayChoices = [30, 14, 7, 3, 1]

    public init(
        categories: Set<String> = ["AI"], ccfRanks: Set<String> = ["A", "B"],
        coreRanks: Set<String> = ["A*", "A", "B", "C", "N"], thcplRanks: Set<String> = ["A", "B", "N"],
        notificationsEnabled: Bool = false, reminderDays: [Int] = [7, 3, 1],
        blockReminders: Bool = true, dateChangeAlerts: Bool = true,
        menuBarStyle: MenuBarStyle = .bar, menuBarSubject: MenuBarSubject? = nil, axisRange: AxisRange = .threeMonths,
        axisLabels: AxisLabels = .dates, rowSize: RowSize = .large, appearance: Appearance = .system
    ) {
        self.categories = categories
        self.ccfRanks = ccfRanks
        self.coreRanks = coreRanks
        self.thcplRanks = thcplRanks
        self.notificationsEnabled = notificationsEnabled
        self.reminderDays = reminderDays
        self.blockReminders = blockReminders
        self.dateChangeAlerts = dateChangeAlerts
        self.menuBarStyle = menuBarStyle
        self.menuBarSubject = menuBarSubject
        self.axisRange = axisRange
        self.axisLabels = axisLabels
        self.rowSize = rowSize
        self.appearance = appearance
    }

    enum CodingKeys: String, CodingKey {
        case categories, ccfRanks, coreRanks, thcplRanks, notificationsEnabled, reminderDays, blockReminders,
            dateChangeAlerts, menuBarStyle, menuBarSubject, axisRange, axisLabels, rowSize, appearance
    }

    /// Fields of earlier builds, read and never written.
    private enum LegacyKeys: String, CodingKey {
        /// The range in months, from before there was a week.
        case axisMonths
    }

    public init(from decoder: any Decoder) throws {
        let defaults = AppSettings()
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        categories = Set(c(.categories, default: defaults.categories.sorted()))
        ccfRanks = Set(c(.ccfRanks, default: defaults.ccfRanks.sorted()))
        coreRanks = Set(c(.coreRanks, default: defaults.coreRanks.sorted()))
        thcplRanks = Set(c(.thcplRanks, default: defaults.thcplRanks.sorted()))
        notificationsEnabled = c(.notificationsEnabled, default: defaults.notificationsEnabled)
        reminderDays = c(.reminderDays, default: defaults.reminderDays)
        blockReminders = c(.blockReminders, default: defaults.blockReminders)
        dateChangeAlerts = c(.dateChangeAlerts, default: defaults.dateChangeAlerts)
        menuBarStyle = c(.menuBarStyle, default: defaults.menuBarStyle)
        menuBarSubject = c(.menuBarSubject, default: nil)
        let legacy = try LenientContainer(decoder, keyedBy: LegacyKeys.self)
        let months: Int? = legacy(.axisMonths, default: nil)
        axisRange = c(.axisRange, default: months.flatMap(AxisRange.init(months:)) ?? defaults.axisRange)
        axisLabels = c(.axisLabels, default: defaults.axisLabels)
        rowSize = c(.rowSize, default: defaults.rowSize)
        appearance = c(.appearance, default: defaults.appearance)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(categories.sorted(), forKey: .categories)
        try c.encode(ccfRanks.sorted(), forKey: .ccfRanks)
        try c.encode(coreRanks.sorted(), forKey: .coreRanks)
        try c.encode(thcplRanks.sorted(), forKey: .thcplRanks)
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encode(reminderDays, forKey: .reminderDays)
        try c.encode(blockReminders, forKey: .blockReminders)
        try c.encode(dateChangeAlerts, forKey: .dateChangeAlerts)
        try c.encode(menuBarStyle, forKey: .menuBarStyle)
        try c.encodeIfPresent(menuBarSubject, forKey: .menuBarSubject)
        try c.encode(axisRange, forKey: .axisRange)
        try c.encode(axisLabels, forKey: .axisLabels)
        try c.encode(rowSize, forKey: .rowSize)
        try c.encode(appearance, forKey: .appearance)
    }
}

/// The language of the generated email summary and of the labels in the timeline image.
public enum MailLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    /// The locale used to format dates in the email. British English writes "16 Nov, 23:59".
    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_GB")
        case .chinese: Locale(identifier: "zh_Hans_CN")
        }
    }
}
