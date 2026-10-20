import AppKit
import DrBarKit
import SwiftUI

/// Sizes shared by every timeline.
///
/// The bars are the point of the app, so they are large and calm: thick rounded rectangles whose
/// right ends are the deadlines, and little else around them. Every list is laid out like a
/// Gantt chart: names in a column, bars beside them on one axis.
public enum Theme {
    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    /// The name column of the menu bar window's lists. Fixed, so the bar areas line up.
    public static let labelWidth: CGFloat = 168
    /// A row of the menu bar window: a name with a short line under it, and the bar beside them.
    /// Rows have no spacing, so the grid and the "today" line run through the whole list.
    public static let rowHeight: CGFloat = 44

    /// A conference bar in the menu bar window. Thick: thin bars look flimsy.
    public static let deadlineBarHeight: CGFloat = 24
    /// The followed conferences under papers and groups, thin and in short rows, so that they
    /// stay out of the way of the work.
    public static let quietBarHeight: CGFloat = 8
    public static let quietRowHeight: CGFloat = 30
    /// A paper's plan in the menu bar window: one segment per block.
    public static let planBarHeight: CGFloat = 24
    /// The line of a group's name, which also holds the flags of its work without blocks.
    public static let laneHeight: CGFloat = 18
    /// Plan bars in the planner, tall enough to hold the block names.
    public static let wideBarHeight: CGFloat = 32
    /// Even a deadline minutes away stays visible, as a short bar with the same corners as the rest.
    public static let minimumBarLength: CGFloat = 20
    /// Space between adjacent blocks.
    public static let blockGap: CGFloat = 2
    /// How tall each block on the same days as others is kept, so that its name and people fit;
    /// the bar grows to give it that.
    public static let trackHeight: CGFloat = 22
    /// Opacity of blocks that are not done; done blocks are solid until they are over.
    public static let undoneOpacity = 0.42
    /// Opacity of what has already passed: a deadline behind today, a block done and over.
    public static let pastOpacity = 0.25
    /// The same for a milestone's diamond, which is small and so needs more to be seen.
    public static let pastMilestoneOpacity = 0.5
    public static let axisHeaderHeight: CGFloat = 14

    /// The corner radius of every bar of a given height: well rounded, yet short of a capsule, so a
    /// short bar never turns into a ball.
    public static func cornerRadius(height: CGFloat) -> CGFloat {
        height * 0.4
    }
}

/// How tall a row of a timeline and its bar are, at the size chosen in Settings. Only large rows
/// write a line under the name and let a bar grow where blocks share days, so that each keeps a
/// track of its own; a smaller bar shares its height among them, and its row cannot be made taller.
public struct RowMetrics: Equatable, Sendable {
    public var rowHeight: CGFloat
    public var barHeight: CGFloat
    public var isLarge: Bool

    public init(rowHeight: CGFloat, barHeight: CGFloat, isLarge: Bool) {
        self.rowHeight = rowHeight
        self.barHeight = barHeight
        self.isLarge = isLarge
    }

    public var grows: Bool {
        isLarge
    }

    public var showsSubtitle: Bool {
        isLarge
    }
}

extension AppSettings.RowSize {
    /// The rows of the menu bar window.
    public var menuBarWindow: RowMetrics {
        switch self {
        case .large: RowMetrics(rowHeight: Theme.rowHeight, barHeight: Theme.planBarHeight, isLarge: true)
        case .medium: RowMetrics(rowHeight: 30, barHeight: 14, isLarge: false)
        case .small: RowMetrics(rowHeight: 20, barHeight: 8, isLarge: false)
        }
    }

    /// The rows of the planner's overview, taller, to hold the names of the blocks.
    public var planner: RowMetrics {
        switch self {
        case .large: RowMetrics(rowHeight: 64, barHeight: Theme.wideBarHeight, isLarge: true)
        case .medium: RowMetrics(rowHeight: 40, barHeight: 20, isLarge: false)
        case .small: RowMetrics(rowHeight: 24, barHeight: 10, isLarge: false)
        }
    }

    /// The conferences under papers and groups, thin and in short rows.
    public var quiet: RowMetrics {
        switch self {
        case .large: RowMetrics(rowHeight: Theme.quietRowHeight, barHeight: Theme.quietBarHeight, isLarge: true)
        case .medium: RowMetrics(rowHeight: 24, barHeight: 7, isLarge: false)
        case .small: RowMetrics(rowHeight: 20, barHeight: 6, isLarge: false)
        }
    }
}

/// How close a deadline is. Decides the bar color and the menu bar icon.
public enum Urgency: Sendable {
    /// More than 30 days, 8–30 days, 4–7 days, 3 days or less.
    case later, soon, near, critical

    public init(secondsLeft: TimeInterval) {
        switch secondsLeft / 86_400 {
        case ...3: self = .critical
        case ...7: self = .near
        case ...30: self = .soon
        default: self = .later
        }
    }

    /// Red and orange only mean "urgent". Everything further away is the calm color, lighter
    /// when it is more than a month out.
    public var color: Color {
        switch self {
        case .critical: .red
        case .near: .orange
        case .soon: Palette.calm
        case .later: Palette.calm.opacity(0.5)
        }
    }
}

public enum Palette {
    /// The accent color, unless the user picked a red or orange accent, which would read as
    /// "urgent"; then blue.
    public static var calm: Color {
        accentIsWarm ? .blue : .accentColor
    }

    static var accentIsWarm: Bool {
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return false }
        return accent.saturationComponent > 0.3 && (accent.hueComponent < 0.13 || accent.hueComponent > 0.94)
    }
}

/// Block colors. System colors adapt to dark mode; red and orange are reserved for "urgent"
/// and "conflict" and never used for blocks.
public enum BlockColor {
    public static func color(for block: TimeBlock) -> Color {
        color(kind: block.kind, customName: block.customName)
    }

    static func color(kind: TimeBlock.Kind, customName: String) -> Color {
        switch kind {
        case .experiments: .blue
        case .writing: .indigo
        case .review: .teal
        case .buffer: .gray
        case .custom: customPalette[paletteIndex(for: customName)]
        }
    }

    static let customPalette: [Color] = [.mint, .cyan, .purple, .brown]

    /// A milestone takes the color of the work it falls in, so that it reads as a point of that
    /// stage: the block on its day, or else the last one before it, or the first after it. Buffers
    /// are passed over, as their gray would say nothing. A plan without work gives its milestones
    /// these colors in turn, in the order of their days.
    public static func color(for milestone: Milestone, among blocks: [TimeBlock], index: Int) -> Color {
        let work = blocks.filter { $0.kind != .buffer }
        let stage =
            work.filter { $0.contains(milestone.day) }.min { $0.start < $1.start }
            ?? work.filter { $0.end < milestone.day }.max { $0.end < $1.end }
            ?? work.filter { $0.start > milestone.day }.min { $0.start < $1.start }
        return stage.map(color(for:)) ?? milestonePalette[index % milestonePalette.count]
    }

    static let milestonePalette: [Color] = [.blue, .indigo, .teal, .mint, .cyan, .purple]

    /// The colors of `milestones` by id, each with its place in the order of their days.
    public static func colors(for milestones: [Milestone], among blocks: [TimeBlock]) -> [UUID: Color] {
        let ordered = milestones.sorted { ($0.day, $0.id.uuidString) < ($1.day, $1.id.uuidString) }
        return Dictionary(
            ordered.enumerated().map { ($0.element.id, color(for: $0.element, among: blocks, index: $0.offset)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// A fixed index per name. Not `hashValue`: Swift seeds hashes per launch, so colors would change.
    static func paletteIndex(for name: String) -> Int {
        name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 } % customPalette.count
    }
}
