import AppKit
import DrBarKit
import SwiftUI

/// A deadline as a timeline draws it.
public struct TimelineDeadline: Identifiable, Equatable, Sendable {
    public enum Style: Int, Comparable, Sendable {
        /// Work with no date to be done by yet: gray, past the end of the axis.
        case undated
        /// Done or passed: faint.
        case closed
        /// Gray.
        case open
        /// The red one.
        case flag

        public static func < (a: Style, b: Style) -> Bool {
            a.rawValue < b.rawValue
        }
    }

    public var deadline: PaperDeadline
    public var date: Date
    public var style: Style
    /// The name beside its flag on a paper's page and in the email's image.
    public var label: String
    /// "CVPR 2027 #4", which its card adds.
    public var context: String?
    /// The paper or item it is a deadline of, where the deadlines of several share a line.
    public var owner: UUID?

    public var id: String {
        owner.map { "\($0)|\(deadline.id)" } ?? deadline.id
    }

    public init(
        deadline: PaperDeadline, date: Date, style: Style, label: String, context: String? = nil, owner: UUID? = nil
    ) {
        self.deadline = deadline
        self.date = date
        self.style = style
        self.label = label
        self.context = context
        self.owner = owner
    }

    /// The flag once its moment has passed is drawn faint, as the others are once done or passed.
    func opacity(now: Date) -> Double {
        style == .closed || (style != .undated && date <= now) ? Theme.pastOpacity : 1
    }
}

extension PaperDeadlines {
    /// Its deadlines that have a date, as a timeline draws them: the flag in red, the others gray,
    /// and faint once done or passed, each named by `label`.
    public func timeline(now: Date, label: (PaperDeadline) -> String = \.shortName) -> [TimelineDeadline] {
        let context = conference?.fullTitle
        return all.compactMap { deadline in
            guard let date = deadline.date else { return nil }
            let style: TimelineDeadline.Style =
                deadline.id == flag?.id ? .flag : deadline.isClosed(now: now) ? .closed : .open
            return TimelineDeadline(
                deadline: deadline, date: date, style: style, label: label(deadline),
                context: deadline.kind == nil ? nil : context)
        }
    }
}

/// The deadlines of a plan bar as ticks: the flag in red, standing out above and below the bar,
/// the others quiet and gray, faint once done or passed. Where the row has room above the bar, a
/// little red flag stands on it beside the red one, its cloth toward the tick. Ticks too close to
/// tell apart show the strongest, and every tick keeps clear of the milestones' diamonds on the
/// bar's top edge.
struct DeadlineTicks: View, Animatable {
    let deadlines: [TimelineDeadline]
    /// Where the diamonds of the milestones stand.
    let diamonds: [Date]
    var axis: TimeAxis
    let now: Date
    let height: CGFloat
    let diamondSize: CGFloat
    /// How much room the row leaves above the bar, which the flag needs.
    var flagRoom: CGFloat = 0

    @Environment(\.colorSchemeContrast) private var contrast

    /// The ticks glide with the bars while the axis moves.
    nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }

    var body: some View {
        Canvas { context, size in
            let top = (size.height - height) / 2
            let flag = Self.flag(
                deadlines, diamonds: diamonds, axis: axis, width: size.width, diamondSize: diamondSize, room: flagRoom)
            for tick in Self.shown(deadlines, axis: axis, width: size.width) {
                let x = axis.x(tick.date, width: size.width)
                let isFlag = tick.style == .flag
                let width: CGFloat = isFlag ? 2 : 1.5
                let length = isFlag ? height + 8 : height + 4
                let rect = CGRect(x: x - width / 2, y: (size.height - length) / 2, width: width, height: length)
                let opacity = tick.opacity(now: now)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                if isFlag {
                    context.fill(path, with: .color(.red.opacity(opacity)))
                } else if contrast == .increased {
                    context.fill(path, with: .color(.primary.opacity(0.6 * opacity)))
                } else {
                    context.fill(path, with: .style(.secondary.opacity(opacity)))
                }
            }
            // Cut around each diamond, so that a tick never runs into one.
            context.blendMode = .destinationOut
            let cut = diamondSize + 3
            for date in diamonds where axis.contains(date) {
                let center = CGPoint(x: axis.x(date, width: size.width), y: size.height / 2 - height / 2)
                var diamond = Path()
                diamond.move(to: CGPoint(x: center.x, y: center.y - cut * 0.71))
                diamond.addLine(to: CGPoint(x: center.x + cut * 0.71, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + cut * 0.71))
                diamond.addLine(to: CGPoint(x: center.x - cut * 0.71, y: center.y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(.black))
            }
            // Clear of the diamonds already, and whole down to the bar.
            if let flag {
                context.blendMode = .normal
                context.fill(
                    flag.path.applying(CGAffineTransform(translationX: 0, y: top)),
                    with: .color(.red.opacity(flag.deadline.opacity(now: now))))
            }
        }
        .allowsHitTesting(false)
    }

    /// The ticks on the axis, the strongest of any closer than 3 pt.
    static func shown(_ deadlines: [TimelineDeadline], axis: TimeAxis, width: CGFloat) -> [TimelineDeadline] {
        let onAxis = deadlines.filter { axis.contains($0.date) }.sorted { $0.date < $1.date }
        var shown: [(tick: TimelineDeadline, x: CGFloat)] = []
        for tick in onAxis {
            let x = axis.x(tick.date, width: width)
            if let last = shown.last, x - last.x < 3 {
                if tick.style > last.tick.style {
                    shown[shown.count - 1] = (tick, x)
                }
            } else {
                shown.append((tick, x))
            }
        }
        return shown.map(\.tick)
    }

    /// The places of the ticks that a block's name and people keep clear of.
    static func places(_ deadlines: [TimelineDeadline], axis: TimeAxis, width: CGFloat) -> [CGFloat] {
        shown(deadlines, axis: axis, width: width).map { axis.x($0.date, width: width) }
    }

    /// The red flag standing on the bar's top edge beside the red tick at `x`: just before it, its
    /// cloth toward the tick, or, near the start of the bar or a diamond, just after it, turned
    /// round, so that the tick and the flag's pole stay two.
    struct Flag {
        let deadline: TimelineDeadline
        let x: CGFloat
        let size: CGFloat
        let isMirrored: Bool

        /// Where it is drawn, measured from the left of the bar and up from its top edge: 1.5 pt
        /// from the tick, which is 2 pt wide.
        var rect: CGRect {
            let width = size * 0.92
            return CGRect(x: isMirrored ? x + 2.5 : x - 2.5 - width, y: -size, width: width, height: size)
        }

        /// A pole and a cloth that waves a little, as the flags of the Deadlines rows.
        var path: Path {
            let rect = rect
            let pole = isMirrored ? rect.maxX - 0.9 : rect.minX
            let cloth = CGRect(
                x: isMirrored ? rect.minX : rect.minX + 0.9, y: rect.minY, width: rect.width - 0.9,
                height: size * 0.62)
            var path = Path(roundedRect: CGRect(x: pole, y: rect.minY, width: 0.9, height: size), cornerRadius: 0.45)
            let near = isMirrored ? cloth.maxX : cloth.minX
            let far = isMirrored ? cloth.minX : cloth.maxX
            let third = (far - near) / 3
            let sag = size * 0.08
            path.move(to: CGPoint(x: near, y: cloth.minY))
            path.addCurve(
                to: CGPoint(x: far, y: cloth.minY + sag), control1: CGPoint(x: near + third, y: cloth.minY - sag),
                control2: CGPoint(x: near + 2 * third, y: cloth.minY + 2 * sag))
            path.addLine(to: CGPoint(x: far, y: cloth.maxY + sag))
            path.addCurve(
                to: CGPoint(x: near, y: cloth.maxY), control1: CGPoint(x: near + 2 * third, y: cloth.maxY + 2 * sag),
                control2: CGPoint(x: near + third, y: cloth.maxY - sag))
            path.closeSubpath()
            return path
        }
    }

    /// Where the flag beside the red tick stands, given the `room` the row leaves above the bar:
    /// nowhere in less than 7 pt, or with diamonds on both sides, where the tick stands alone.
    static func flag(
        _ deadlines: [TimelineDeadline], diamonds: [Date], axis: TimeAxis, width: CGFloat, diamondSize: CGFloat,
        room: CGFloat
    ) -> Flag? {
        guard room >= 7, let red = shown(deadlines, axis: axis, width: width).first(where: { $0.style == .flag })
        else { return nil }
        let x = axis.x(red.date, width: width)
        let size = min(9, room - 1)
        let marks = diamonds.filter { axis.contains($0) }.map { axis.x($0, width: width) }
        return [false, true].map { Flag(deadline: red, x: x, size: size, isMirrored: $0) }.first { flag in
            let rect = flag.rect
            return rect.minX >= 0 && rect.maxX <= width
                && !marks.contains { abs($0 - rect.midX) < (diamondSize + rect.width) / 2 + 1 }
        }
    }
}

/// What the Deadlines row of a paper's page lets the user do: select a deadline of its own with a
/// click and drag it to another day, open it or a conference's date with a double click, tick one
/// off, make one the main deadline, delete it, and add one with a double click on an empty day.
@MainActor
public struct DeadlineEditing {
    public var selection: UUID?
    /// The days a dragged deadline is felt snapping onto.
    public var guides: Set<Day>
    /// Whether an own deadline can be made the main one, which it is not yet.
    public var canMakeMain: (UUID) -> Bool
    public var select: (UUID?) -> Void
    /// Its editor, or the details of a conference's date.
    public var open: (PaperDeadline) -> Void
    /// Adds a deadline on that day, or, without one, where a new one goes.
    public var add: (Day?) -> Void
    /// Moves an own deadline that many days, keeping its time in its own time zone.
    public var move: (UUID, Int) -> Void
    public var toggleDone: (PaperDeadline) -> Void
    public var makeMain: (UUID) -> Void
    public var delete: (UUID) -> Void
    /// Whether an own deadline moved that many days would leave work running past it.
    public var wouldConflict: (UUID, Int) -> Bool
    public var pan: ((CGFloat) -> Void)?

    public init(
        selection: UUID?, guides: Set<Day>, canMakeMain: @escaping (UUID) -> Bool, select: @escaping (UUID?) -> Void,
        open: @escaping (PaperDeadline) -> Void, add: @escaping (Day?) -> Void, move: @escaping (UUID, Int) -> Void,
        toggleDone: @escaping (PaperDeadline) -> Void, makeMain: @escaping (UUID) -> Void,
        delete: @escaping (UUID) -> Void, wouldConflict: @escaping (UUID, Int) -> Bool,
        pan: ((CGFloat) -> Void)? = nil
    ) {
        self.selection = selection
        self.guides = guides
        self.canMakeMain = canMakeMain
        self.select = select
        self.open = open
        self.add = add
        self.move = move
        self.toggleDone = toggleDone
        self.makeMain = makeMain
        self.delete = delete
        self.wouldConflict = wouldConflict
        self.pan = pan
    }
}

/// Where each deadline of a timeline is drawn, by `PaperDeadline.id`, so that a popover can point
/// at one.
public struct DeadlineBounds: PreferenceKey {
    public static var defaultValue: [String: Anchor<CGRect>] { [:] }

    public static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The Deadlines row of a paper's timeline, and the line of a group's work without blocks: a flag
/// at each deadline with its name beside it, the red one for the flag, placed so that no two names
/// and no name and flag touch. Deadlines on nearly the same moment stand as one flag, named for all
/// of them.
struct DeadlineTrack: View, Animatable {
    var axis: TimeAxis
    let now: Date
    let deadlines: [TimelineDeadline]
    let editing: DeadlineEditing?
    /// The deadline under the pointer, whose line the timeline draws through the work.
    @Binding var hovered: String?
    /// Leaves out the flags too close to leave the red one room for its name, where the row cannot
    /// be hovered for the names, as in the email's image.
    var leavesOutCrowded = false
    var height = Self.height
    /// Set on the line of a group's work, where what stands beyond the axis stands at its edge.
    var lane: Lane?

    /// What the flags of a group's line say and do: they are named for their work, a click opens
    /// it, and their menu and card are the work's own, or one for each piece of work where several
    /// stand as one.
    struct Lane {
        let titles: [UUID: String]
        let open: (UUID) -> Void
        let menu: (UUID) -> AnyView
        let card: (UUID) -> HoverCardSource?

        /// The work of a flag's deadlines, each once, in their order.
        func owners(of members: [TimelineDeadline]) -> [UUID] {
            members.compactMap(\.owner).reduce(into: []) { owners, id in
                if !owners.contains(id) {
                    owners.append(id)
                }
            }
        }

        /// A flag's name: the title of each piece of work once, followed by the names of its other
        /// deadlines on the flag.
        func label(of members: [TimelineDeadline]) -> String {
            owners(of: members).map { owner in
                let others = members.filter { $0.owner == owner && !Self.isNamedByTitle($0) }.map(\.label)
                return ([titles[owner] ?? ""] + others).joined(separator: " · ")
            }
            .joined(separator: " · ")
        }

        /// A deadline's name in a card of several: its work's title, and its own name unless the
        /// title is enough.
        func name(of deadline: TimelineDeadline) -> String {
            let title = deadline.owner.flatMap { titles[$0] } ?? ""
            return Self.isNamedByTitle(deadline) ? title : "\(title) · \(deadline.label)"
        }

        /// The one a piece of work is marked by, or what stands for work with no date.
        private static func isNamedByTitle(_ deadline: TimelineDeadline) -> Bool {
            deadline.style == .flag || deadline.style == .undated
        }

        /// What stands at an edge as an arrow: each red flag beyond the axis, work with no date, and,
        /// for work with nothing else to show, its deadline nearest to the axis, so that no work goes
        /// without a mark.
        static func beyond(_ deadlines: [TimelineDeadline], axis: TimeAxis) -> Set<String> {
            var ids = Set(deadlines.filter { isNamedByTitle($0) && !axis.contains($0.date) }.map(\.id))
            let shown = Set(deadlines.filter { axis.contains($0.date) || ids.contains($0.id) }.compactMap(\.owner))
            for owner in Set(deadlines.compactMap(\.owner)).subtracting(shown) {
                let theirs = deadlines.filter { $0.owner == owner }
                let nearest =
                    theirs.filter { $0.date > axis.end }.min { $0.date < $1.date }
                    ?? theirs.max { $0.date < $1.date }
                if let nearest {
                    ids.insert(nearest.id)
                }
            }
            return ids
        }
    }

    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.axisLabels) private var axisLabels
    @GestureState private var drag: DeadlineDrag?
    @State private var lastDays: Int?
    @State private var cancelledDrag: UUID?
    @State private var cancellation = DragCancellation()
    @State private var edgeScroll = EdgeScroll()
    @State private var dragAnchor = DragAnchor<Date>()

    static let height: CGFloat = 30

    /// Moves with the axis frame by frame, as the grid and the ticks do, so that what crosses an
    /// edge slides across it rather than fading in place.
    nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let marks = marks(width: width)
            ZStack(alignment: .leading) {
                if let editing {
                    surface(editing: editing, width: width)
                }
                ForEach(marks) { mark in
                    flag(mark, width: width)
                        .offset(x: mark.offset)
                        .zIndex(mark.isDragged ? 1 : 0)
                }
            }
            .coordinateSpace(.named(TrackSpace()))
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// A flag on the row: one deadline, or several on nearly the same moment, with its name placed.
    struct Mark: Identifiable {
        var members: [TimelineDeadline]
        var lead: TimelineDeadline
        /// The deadline of its own that a click selects and a drag moves: the selected one, or else
        /// the first.
        var ownID: UUID?
        var x: CGFloat
        var label: String
        /// How many more pieces of work it stands for, which its shortened name never cuts off.
        var suffix: String?
        var placement: LabelPlacement.Placement
        var isDragged: Bool
        /// The edge its deadline is beyond, where it stands as an arrow.
        var beyond: HorizontalEdge?

        /// The deadline it drags, so that the flag holding a drag stays the same view when the
        /// deadline is dragged away from the others.
        var id: String {
            ownID?.uuidString ?? lead.id
        }

        /// Whether it stands as an arrow at the edge its deadline is beyond, rather than as a flag.
        var isArrow: Bool {
            beyond == .leading || (beyond == .trailing && lead.style != .undated)
        }

        /// A flag; an arrow at the edge its deadline is beyond; or, for work with no date yet, an
        /// empty flag at the end.
        var symbol: String {
            switch beyond {
            case .leading: "chevron.left"
            case .trailing: isArrow ? "chevron.right" : "flag"
            case nil: "flag.fill"
            }
        }

        /// Facing back, as a flag does at the end of the row.
        var isFlipped: Bool {
            placement.isMirrored && !isArrow
        }

        /// What a double click opens: the deadline a click selects, or else the one it is drawn as.
        var opened: PaperDeadline {
            (members.first { $0.deadline.ownID != nil && $0.deadline.ownID == ownID } ?? lead).deadline
        }

        /// Where the mark's frame starts: before the flag when the name goes first.
        var offset: CGFloat {
            let glyph = placement.isMirrored ? x - LabelPlacement.glyph : x - 1
            return placement.side == .before ? glyph - LabelPlacement.gap - placement.width : glyph
        }
    }

    /// The flags on the axis, grouped where they nearly meet, with their names placed. A deadline
    /// being dragged stands on its own and is named first. On a group's line, a flag of several
    /// pieces of work without the room for all their names is named for the first, and how many
    /// more.
    private func marks(width: CGFloat) -> [Mark] {
        // Once Esc has let go of a drag, it no longer counts, though the button is still down.
        let draggedID = drag.flatMap { $0.id == cancelledDrag ? nil : $0.id }
        let isDragged = { (deadline: TimelineDeadline) in draggedID != nil && deadline.deadline.ownID == draggedID }
        let beyond = lane == nil ? [] : Lane.beyond(deadlines, axis: axis)
        var shown = deadlines.filter { axis.contains($0.date) || isDragged($0) || beyond.contains($0.id) }
        if let drag, let index = shown.firstIndex(where: isDragged) {
            shown[index].date = drag.date(
                on: axis, original: shown[index].date, timeZone: shown[index].deadline.timeZone)
        }
        func edge(of deadline: TimelineDeadline) -> HorizontalEdge? {
            guard beyond.contains(deadline.id) else { return nil }
            return deadline.date > axis.end ? .trailing : .leading
        }
        func x(_ deadline: TimelineDeadline) -> CGFloat {
            switch edge(of: deadline) {
            case .leading: 1
            case .trailing: width - 1
            case nil: axis.x(deadline.date, width: width)
            }
        }
        let others = shown.filter { !isDragged($0) }
        let xs = others.map { Double(x($0)) }
        var groups = LabelPlacement.clusters(xs, width: width).map { $0.map { others[$0] } }
        groups += shown.filter(isDragged).map { [$0] }

        func lead(of group: [TimelineDeadline]) -> TimelineDeadline {
            group.max { ($0.style, -$0.date.timeIntervalSince1970) < ($1.style, -$1.date.timeIntervalSince1970) }!
        }
        func label(of group: [TimelineDeadline]) -> String {
            lane?.label(of: group) ?? group.map(\.label).joined(separator: " · ")
        }
        var shortened: [Int: (name: String, suffix: String)] = [:]
        func name(_ index: Int) -> (label: String, suffix: String?) {
            shortened[index].map { ($0.name, $0.suffix) } ?? (label(of: groups[index]), nil)
        }
        func mark(_ index: Int) -> LabelPlacement.Mark {
            let lead = lead(of: groups[index])
            let isFirst = isDragged(lead) || lead.style == .flag
            let name = name(index)
            return LabelPlacement.Mark(
                x: x(lead), width: TextWidth.of(name.label + (name.suffix ?? "")),
                rank: isFirst ? 0 : lead.style == .open ? 1 + index : 1000,
                minimum: name.suffix.map { TextWidth.of($0) + 24 } ?? 36,
                // Its red tells whose the flag's name is, so it may come closer to the next flag.
                clearance: lead.style == .flag ? LabelPlacement.nearClearance : LabelPlacement.clearance)
        }
        if leavesOutCrowded {
            let left = LabelPlacement.yielding(groups.indices.map(mark), width: width)
            groups = groups.indices.filter { !left.contains($0) }.map { groups[$0] }
        }
        var placements = LabelPlacement.place(groups.indices.map(mark), width: width)
        if let lane {
            for index in groups.indices where placements[index].width < TextWidth.of(label(of: groups[index])) {
                let owners = lane.owners(of: groups[index])
                if owners.count > 1,
                    let first = (lead(of: groups[index]).owner ?? owners.first).flatMap({ lane.titles[$0] })
                {
                    shortened[index] = (first, " +\(owners.count - 1)")
                }
            }
            if !shortened.isEmpty {
                placements = LabelPlacement.place(groups.indices.map(mark), width: width)
            }
        }
        return groups.indices.map { index in
            let lead = lead(of: groups[index])
            let own = groups[index].compactMap(\.deadline.ownID)
            let name = name(index)
            return Mark(
                members: groups[index], lead: lead, ownID: own.first { $0 == editing?.selection } ?? own.first,
                x: x(lead), label: name.label, suffix: name.suffix, placement: placements[index],
                isDragged: isDragged(lead), beyond: edge(of: lead))
        }
    }

    private func flag(_ mark: Mark, width: CGFloat) -> some View {
        let lead = mark.lead
        // The flag faint once its moment has passed; the others quiet, and fainter once closed.
        let color: AnyShapeStyle =
            switch lead.style {
            case .flag: AnyShapeStyle(Color.red.opacity(lead.opacity(now: now)))
            case .open: AnyShapeStyle(.secondary)
            case .closed, .undated: AnyShapeStyle(.tertiary)
            }
        let isSelected = mark.ownID != nil && mark.ownID == editing?.selection && !mark.isDragged
        let glyph = Image(systemName: mark.symbol)
            .font(.system(size: 9, weight: .semibold))
            .scaleEffect(x: mark.isFlipped ? -1 : 1)
            .foregroundStyle(color)
            .frame(width: LabelPlacement.glyph + 1, height: height)
            .contentShape(Rectangle())
            .overlay {
                // Close around the flag, clear of its name.
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isFocused && activeState == .key ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary),
                            lineWidth: 1.5
                        )
                        .frame(width: LabelPlacement.glyph + 5, height: 18)
                }
            }
            .overlay {
                if let editing, let id = mark.ownID,
                    let deadline = mark.members.first(where: { $0.deadline.ownID == id })
                {
                    grip(deadline, id: id, editing: editing, width: width)
                }
            }
            .anchorPreference(key: DeadlineBounds.self, value: .bounds) { anchor in
                Dictionary(mark.members.map { ($0.id, anchor) }, uniquingKeysWith: { first, _ in first })
            }
        let name = mark.placement.side.map { _ in
            HStack(spacing: 0) {
                Text(mark.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let suffix = mark.suffix {
                    Text(suffix)
                        .fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: mark.placement.width, alignment: mark.placement.side == .before ? .trailing : .leading)
        }
        return clickable(
            HStack(spacing: LabelPlacement.gap) {
                if mark.placement.side == .before, let name {
                    name
                }
                glyph
                if mark.placement.side == .after, let name {
                    name
                }
            }
            .contentShape(Rectangle()),
            mark: mark
        )
        .onContinuousHover { phase in
            switch phase {
            case .active: hovered = lead.id
            case .ended: if hovered == lead.id { hovered = nil }
            }
        }
        .hoverCard(id: "deadline|" + lead.id) {
            guard !mark.isDragged else { return nil }
            guard let lane else { return .deadlines(mark.members.map { ($0.deadline, $0.context) }, now: now) }
            let owners = lane.owners(of: mark.members)
            guard owners.count > 1 else { return owners.first.flatMap(lane.card)?.make() }
            return .dueWork(
                owners.compactMap { lane.titles[$0] }, mark.members.map { (lane.name(of: $0), $0.deadline) }, now: now)
        }
        .overlay(alignment: .top) {
            if mark.isDragged, let editing, let id = mark.ownID {
                DragLabel(
                    parts: dragParts(lead), isPastDeadline: editing.wouldConflict(id, drag?.days(on: axis) ?? 0)
                )
                .alignmentGuide(.top) { $0[.bottom] + 2 }
            }
        }
    }

    /// When the dragged deadline would be, in the time zone it was entered in, "Mon, Nov 23 23:59
    /// AoE", and the days from today where the axis counts them.
    private func dragParts(_ deadline: TimelineDeadline) -> [String] {
        [
            axisLabels.wrappedValue.showsDates
                ? DeadlineText.ownTime(deadline.date, deadline.deadline.timeZone)
                    ?? DeadlineText.localDateTime(deadline.date) : nil,
            axisLabels.wrappedValue.showsDays ? RelativeDayText.label(Day(now).days(to: Day(deadline.date))) : nil,
        ]
        .compactMap { $0 }
    }

    /// A flag and its name: a click selects its deadline of its own, a double click opens it, or
    /// what the flag is drawn as, and its menu offers what can be done with each of its deadlines.
    /// On a group's line, a click opens the flag's work.
    @ViewBuilder
    private func clickable(_ flag: some View, mark: Mark) -> some View {
        if let editing {
            flag
                .gesture(
                    TapGesture(count: 2).onEnded { editing.open(mark.opened) }
                        .simultaneously(with: TapGesture().onEnded { editing.select(mark.ownID) })
                )
                .contextMenu { DeadlineMenu(mark.members.map(\.deadline), editing: editing) }
        } else if let lane {
            let owners = lane.owners(of: mark.members)
            flag
                .onTapGesture {
                    if let owner = mark.lead.owner ?? owners.first {
                        lane.open(owner)
                    }
                }
                .contextMenu {
                    if owners.count == 1 {
                        lane.menu(owners[0])
                    } else {
                        ForEach(owners, id: \.self) { owner in
                            Menu(lane.titles[owner] ?? "") { lane.menu(owner) }
                        }
                    }
                }
        } else {
            flag
        }
    }

    /// Laid over a flag that holds a deadline of its own: drags it a day at a time.
    private func grip(_ deadline: TimelineDeadline, id: UUID, editing: DeadlineEditing, width: CGFloat) -> some View {
        // Measured from the deadline as it was, not as it is drawn while it moves.
        let original = deadlines.first { $0.id == deadline.id }?.date ?? deadline.date
        return Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard drag == nil else { return }
                switch phase {
                case .active: NSCursor.openHand.set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(TrackSpace()))
                    .updating($drag) { value, state, _ in
                        state = DeadlineDrag(
                            id: id, anchor: state?.anchor ?? moment(value.startLocation, width),
                            x: value.location.x, rowWidth: width)
                    }
                    .onChanged { value in
                        if dragAnchor.value(for: value) == nil {
                            // A new drag, whatever became of the one before.
                            dragAnchor = DragAnchor(moment(value.startLocation, width), at: value.startLocation)
                            lastDays = nil
                            if cancelledDrag == id {
                                cancelledDrag = nil
                            }
                        }
                        guard cancelledDrag != id else { return }
                        cancellation.listen {
                            cancelledDrag = id
                            edgeScroll.stop()
                        }
                        NSCursor.closedHand.set()
                        edgeScroll.follow(x: value.location.x, width: width, pan: editing.pan)
                        let moved = days(value, width)
                        guard moved != lastDays else { return }
                        let lands = DeadlineTimeZone.moving(original, byDays: moved, in: deadline.deadline.timeZone)
                        if lastDays != nil, editing.guides.contains(Day(lands)) {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        lastDays = moved
                    }
                    .onEnded { value in
                        cancellation.stop()
                        edgeScroll.stop()
                        let moved = days(value, width)
                        dragAnchor = DragAnchor()
                        lastDays = nil
                        NSCursor.openHand.set()
                        guard cancelledDrag != id else {
                            cancelledDrag = nil
                            return
                        }
                        if moved != 0 {
                            editing.move(id, moved)
                        }
                    }
            )
    }

    /// The moment under the pointer at `location`, in the row.
    private func moment(_ location: CGPoint, _ width: CGFloat) -> Date {
        axis.date(atX: location.x, width: width)
    }

    private func days(_ value: DragGesture.Value, _ width: CGFloat) -> Int {
        wholeDays(
            from: dragAnchor.value(for: value) ?? moment(value.startLocation, width), to: moment(value.location, width))
    }

    /// Empty days: a double click adds a deadline there, a click clears the selection.
    private func surface(editing: DeadlineEditing, width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                TapGesture()
                    .onEnded { editing.select(nil) }
                    .simultaneously(
                        with: SpatialTapGesture(count: 2).onEnded { value in
                            let x = min(max(value.location.x, 0), width)
                            editing.add(Day(axis.date(atX: x, width: width)))
                        })
            )
    }
}

/// What can be done with deadlines, in the menu of a flag on the timeline and of a row in a list:
/// show their conference's details, edit those of their own, tick them off, make one the main
/// deadline, delete one. The deadlines of one flag each have a section.
public struct DeadlineMenu: View {
    let deadlines: [PaperDeadline]
    let editing: DeadlineEditing

    public init(_ deadlines: [PaperDeadline], editing: DeadlineEditing) {
        self.deadlines = deadlines
        self.editing = editing
    }

    public var body: some View {
        // The same details for every date of the round.
        if let conference = deadlines.first(where: { $0.ownID == nil }) {
            Button {
                editing.open(conference)
            } label: {
                Text("Show Details", bundle: .module)
            }
        }
        if deadlines.count == 1, let deadline = deadlines.first {
            items(for: deadline)
        } else {
            ForEach(deadlines) { deadline in
                Section {
                    items(for: deadline)
                }
            }
        }
    }

    @ViewBuilder
    private func items(for deadline: PaperDeadline) -> some View {
        if let id = deadline.ownID {
            Button {
                editing.open(deadline)
            } label: {
                Text("Edit “\(deadline.name)”…", bundle: .module)
            }
            doneButton(deadline)
            if editing.canMakeMain(id) {
                Button {
                    editing.makeMain(id)
                } label: {
                    Text("Make Main Deadline", bundle: .module)
                }
            }
            Divider()
            Button(role: .destructive) {
                editing.delete(id)
            } label: {
                Text("Delete “\(deadline.name)”", bundle: .module)
            }
        } else {
            doneButton(deadline)
        }
    }

    /// Ticks it off, named after it where a menu holds the dates of several.
    @ViewBuilder
    private func doneButton(_ deadline: PaperDeadline) -> some View {
        let isNamed = deadlines.count > 1 && deadline.ownID == nil
        switch deadline.completion {
        case .tick:
            Button {
                editing.toggleDone(deadline)
            } label: {
                switch (deadline.isDone, isNamed) {
                case (true, true): Text("Mark “\(deadline.name)” as Not Done", bundle: .module)
                case (false, true): Text("Mark “\(deadline.name)” as Done", bundle: .module)
                case (true, false): Text("Mark as Not Done", bundle: .module)
                case (false, false): Text("Mark as Done", bundle: .module)
                }
            }
            .disabled(deadline.isDoneByStage)
        case .submission:
            Button {
                editing.toggleDone(deadline)
            } label: {
                deadline.isDone
                    ? Text("Mark as Not Submitted", bundle: .module) : Text("Mark as Submitted", bundle: .module)
            }
            .disabled(deadline.isDoneByStage)
        case .decision:
            EmptyView()
        }
    }
}

/// An own deadline while it is dragged: the moment that was under the pointer when the drag
/// began, and where the pointer is now in the row.
struct DeadlineDrag: Equatable {
    let id: UUID
    let anchor: Date
    var x: CGFloat
    var rowWidth: CGFloat

    func days(on axis: TimeAxis) -> Int {
        wholeDays(from: anchor, to: axis.date(atX: x, width: rowWidth))
    }

    /// Where the deadline lands: whole days later in its own time zone, as moving it does.
    func date(on axis: TimeAxis, original: Date, timeZone: String) -> Date {
        DeadlineTimeZone.moving(original, byDays: days(on: axis), in: timeZone)
    }
}

/// How wide a text is written in the system font, measured once for each text, size and weight,
/// the same in the window and in the email's image.
@MainActor
enum TextWidth {
    private static var cache: [String: CGFloat] = [:]

    /// In one of the small text styles, as the axis and the deadlines are labelled.
    static func of(
        _ text: String, style: NSFont.TextStyle = .caption1, weight: NSFont.Weight = .regular
    ) -> Double {
        of(text, size: NSFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
    }

    static func of(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> Double {
        let key = "\(size)|\(weight.rawValue)|\(text)"
        if let width = cache[key] { return Double(width) }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        cache[key] = width
        return Double(width)
    }
}
