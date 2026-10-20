import DrBarKit
import SwiftUI

extension TimeBlock.Kind {
    public var localizedName: String {
        switch self {
        case .experiments: String(localized: "Experiments", bundle: .module, comment: "Time block kind")
        case .writing: String(localized: "Writing", bundle: .module, comment: "Time block kind")
        case .review: String(localized: "Internal review", bundle: .module, comment: "Time block kind")
        case .buffer: String(localized: "Buffer", bundle: .module, comment: "Time block kind")
        case .custom:
            String(localized: "Custom", bundle: .module, comment: "Time block kind with a name of the user's choice")
        }
    }
}

extension TimeBlock {
    /// The name shown in lists and bars.
    public var displayName: String {
        guard kind == .custom else { return kind.localizedName }
        let name = customName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Untitled block", bundle: .module) : name
    }
}

extension Milestone {
    /// The name shown on the timeline and in lists.
    public var displayName: String {
        let name = title.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Untitled milestone", bundle: .module) : name
    }
}

extension CustomDeadline {
    /// The name it was given, or "Deadline" without one.
    public var displayName: String {
        let name = title.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Deadline", bundle: .module) : name
    }
}

extension Paper.Stage {
    public var localizedName: String {
        switch self {
        case .idea: String(localized: "Idea", bundle: .module, comment: "Paper stage")
        case .experiments: String(localized: "Experiments", bundle: .module, comment: "Paper stage")
        case .writing: String(localized: "Writing", bundle: .module, comment: "Paper stage")
        case .submitted: String(localized: "Submitted", bundle: .module, comment: "Paper stage")
        case .decided: String(localized: "Decided", bundle: .module, comment: "Paper stage")
        }
    }
}

extension DeadlineKind {
    /// "Paper submission", "Abstract registration"…
    public var localizedName: String {
        switch self {
        case .abstract: String(localized: "Abstract registration", bundle: .module)
        case .paper: String(localized: "Paper submission", bundle: .module)
        case .rebuttal: String(localized: "Rebuttal", bundle: .module, comment: "Rebuttal period date of a conference")
        case .decision:
            String(localized: "Notification", bundle: .module, comment: "Date when acceptance decisions are sent")
        }
    }

    /// "Abstract", "Paper", "Rebuttal", "Notification": where it is plain whose they are.
    public var shortName: String {
        switch self {
        case .abstract: String(localized: "Abstract", bundle: .module, comment: "Short for the abstract registration")
        case .paper: String(localized: "Paper", bundle: .module, comment: "Short for the paper submission")
        case .rebuttal, .decision: localizedName
        }
    }
}

extension PaperDeadline {
    /// "Abstract registration", or the name it was given; "Deadline" without one.
    public var name: String {
        if let kind { return kind.localizedName }
        let title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? String(localized: "Deadline", bundle: .module) : title
    }

    /// What the Deadlines row of a timeline writes beside its flag, where the venue is plain from
    /// the page: "Abstract", "Paper", "Rebuttal", "Notification", or an own deadline's name.
    public var shortName: String {
        kind?.shortName ?? name
    }

    /// The same beside a flag of work without blocks: an own deadline without a name by its day,
    /// which is all there is to say about it.
    public var flagName: String {
        guard kind == nil, title.trimmingCharacters(in: .whitespaces).isEmpty, let date else { return shortName }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension PaperDeadlines {
    /// What a row shows under a paper's or an item's name: "CVPR 2027", the name of the own
    /// deadline it aims at, or when that is due: "Due Tue, Nov 10".
    public var displayTitle: String? {
        if let title { return title }
        return main?.date.map(DeadlineText.due)
    }
}

extension RecipientGroup {
    /// The group's name, or the name of its kind.
    public var displayName: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return switch kind {
        case .supervisors: String(localized: "Supervisors", bundle: .module, comment: "Group of email recipients")
        case .collaborators: String(localized: "Collaborators", bundle: .module, comment: "Group of email recipients")
        case .other: String(localized: "Untitled group", bundle: .module)
        }
    }
}

extension PlanStatus {
    /// The SF Symbol shown next to a paper's name; `nil` when there is nothing to flag.
    public var symbolName: String? {
        switch self {
        case .behind: "tortoise.fill"
        case .conflict: "exclamationmark.triangle.fill"
        case .noPlan, .onTrack: nil
        }
    }

    public var color: Color {
        self == .conflict ? .red : .orange
    }

    public var localizedDescription: String {
        switch self {
        case .noPlan: String(localized: "Not planned", bundle: .module)
        case .onTrack: String(localized: "On track", bundle: .module)
        case .behind: String(localized: "Behind: a block or milestone is overdue", bundle: .module)
        case .conflict: String(localized: "Conflict: work runs past its deadline", bundle: .module)
        }
    }
}

extension AppSettings.MenuBarStyle {
    public var localizedName: String {
        switch self {
        case .bar: String(localized: "Symbol and name", bundle: .module, comment: "Menu bar style")
        case .stack: String(localized: "Two deadlines", bundle: .module, comment: "Menu bar style")
        case .days: String(localized: "Symbol, name and days", bundle: .module, comment: "Menu bar style")
        case .iconOnly: String(localized: "Symbol only", bundle: .module, comment: "Menu bar style")
        }
    }
}

/// The ten CCF categories, and the ranks of the three lists ccfddl gives: CCF's, CORE's and
/// TH-CPL, Tsinghua's.
public enum CCFCategory {
    public static let all = ["AI", "CG", "CT", "DB", "DS", "HI", "MX", "NW", "SC", "SE"]
    public static let ranks = ["A", "B", "C", "N"]
    public static let coreRanks = ["A*", "A", "B", "C", "N"]
    public static let thcplRanks = ["A", "B", "N"]

    public static func name(_ code: String) -> String {
        switch code {
        case "AI": String(localized: "Artificial intelligence", bundle: .module)
        case "CG": String(localized: "Graphics and multimedia", bundle: .module)
        case "CT": String(localized: "Theory", bundle: .module)
        case "DB": String(localized: "Databases and data mining", bundle: .module)
        case "DS": String(localized: "Architecture and systems", bundle: .module)
        case "HI": String(localized: "Human–computer interaction", bundle: .module)
        case "MX": String(localized: "Interdisciplinary", bundle: .module)
        case "NW": String(localized: "Networks", bundle: .module)
        case "SC": String(localized: "Security", bundle: .module)
        case "SE": String(localized: "Software engineering", bundle: .module)
        default: code
        }
    }

    public static func rankName(_ rank: String) -> String {
        rank == "N"
            ? String(localized: "Not ranked", bundle: .module)
            : String(localized: "CCF \(rank)", bundle: .module, comment: "CCF rank, e.g. CCF A")
    }

    public static func coreRankName(_ rank: String) -> String {
        rank == "N" ? String(localized: "Not ranked", bundle: .module) : "CORE \(rank)"
    }

    public static func thcplRankName(_ rank: String) -> String {
        rank == "N" ? String(localized: "Not listed", bundle: .module) : "TH-CPL \(rank)"
    }
}

/// Strings used in more than one place.
public enum SharedText {
    public static var today: String { String(localized: "Today", bundle: .module, comment: "Label of the today line") }
    public static var notAnnounced: String { String(localized: "Not announced", bundle: .module) }
    public static var passed: String { String(localized: "passed", bundle: .module, comment: "A deadline in the past") }
    public static var unreadable: String { String(localized: "Date unreadable", bundle: .module) }
    public static var unrecognizedTimeZone: String { String(localized: "Unrecognized time zone", bundle: .module) }
    public static var deadlineNotAnnounced: String { String(localized: "Deadline not announced", bundle: .module) }
    public static var localTime: String { String(localized: "local time", bundle: .module) }
    public static var milestones: String {
        String(localized: "Milestones", bundle: .module, comment: "Row of a paper's timeline")
    }
    public static var deadlines: String {
        String(localized: "Deadlines", bundle: .module, comment: "Row of a paper's timeline")
    }
    public static var conference: String {
        String(localized: "Conference", bundle: .module, comment: "When and where a conference takes place")
    }
}

extension ItemGroup {
    /// The group's name, or "Untitled Group" while it has none.
    public var displayName: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Untitled Group", bundle: .module) : name
    }
}

extension Paper {
    /// The title, or "Untitled paper" or "Untitled item" while there is none.
    public var displayTitle: String {
        guard title.isEmpty else { return title }
        return isPaper
            ? String(localized: "Untitled paper", bundle: .module) : String(localized: "Untitled item", bundle: .module)
    }
}
