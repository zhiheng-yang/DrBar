import AppKit
import DrBarKit
import DrBarUI
import SwiftUI

/// The menu bar item: what it is about, its name and its days, in a frame whose thick outline is a
/// clock of its own. Time goes round the outline clockwise, to the deadline in the middle of its
/// top edge. For the next deadline, the outline is the time from when its work started, and the
/// stretch from now to the top the time left, in the color of how close it is; for a paper or an
/// item picked with its plan, the plan goes round from its first day, a stretch per block in the
/// block's color, done ones solid, with a bead at today, so that what is done, what is now and what
/// is left show at once. Inside, clear of the outline, stands what it is about: the graduation cap,
/// a page, a group's symbol, or a warning in the last three days. The two-deadline style frames the
/// days of each of the next two deadlines.
///
/// `MenuBarExtra` labels only take text and images, so everything is rendered into one image, once
/// for a light menu bar and once for a dark one. The image draws whichever the menu bar it is on
/// asks for, as a template image would be tinted, so that its text always reads.
struct MenuBarLabelView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let style = store.settings.menuBarStyle
        let glance = store.menuBarGlance(limit: style == .stack ? MenuBarLabel.stackCount : 1)
        Image(nsImage: MenuBarLabel.image(glance, now: store.now, style: style))
            .accessibilityLabel(MenuBarLabel.spokenLabel(glance, now: store.now))
            .onAppear {
                // The label lives as long as the app, so its openWindow action can also serve
                // notifications.
                store.openWindowAction = openWindow
            }
    }
}

/// What the menu bar item draws.
struct MenuBarGlance: Equatable {
    /// A paper or an item picked for the menu bar.
    struct Plan: Equatable {
        var name: String
        var blocks: [TimeBlock]
        var deadline: Date?
        var status: PlanStatus
        /// A page for a paper, its group's symbol for an item.
        var symbol: String
    }

    /// The deadlines to count down to, nearest first.
    var upcoming: [FollowedDeadline]
    var plan: Plan?
}

@MainActor
enum MenuBarLabel {
    static let stackCount = 2
    static let maxNameLength = 7
    /// One round of the frame for a deadline that no work has started, such as a conference
    /// followed on its own.
    static let countdownScale: TimeInterval = 30 * 86_400
    private static var cache: (content: LabelContent, scale: CGFloat, image: NSImage)?

    static func image(_ glance: MenuBarGlance, now: Date, style: AppSettings.MenuBarStyle) -> NSImage {
        let content = LabelContent(
            frames: frames(glance, now: now, style: style),
            accent: NSColor.controlAccentColor.usingColorSpace(.sRGB),
            increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        // As sharp as the sharpest screen it may be on.
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2

        // Re-render only when something visible changed; the label is asked every minute.
        if let cache, cache.content == content, cache.scale == scale { return cache.image }
        guard let light = render(content, .light, scale: scale), let dark = render(content, .dark, scale: scale)
        else {
            let symbol = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: "DrBar")!
            symbol.isTemplate = true
            return symbol
        }
        let size = NSSize(width: CGFloat(light.width) / scale, height: CGFloat(light.height) / scale)
        let image = NSImage(size: size, flipped: false) { @Sendable rect in
            let appearance = NSAppearance.currentDrawing().bestMatch(from: [
                .aqua, .darkAqua, .vibrantLight, .vibrantDark,
            ])
            let isDark = appearance == .darkAqua || appearance == .vibrantDark
            NSGraphicsContext.current?.cgContext.draw(isDark ? dark : light, in: rect)
            return true
        }
        image.cacheMode = .never
        cache = (content, scale, image)
        return image
    }

    private static func render(_ content: LabelContent, _ scheme: ColorScheme, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, scheme))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// What the item of `glance` frames in `style`: what it is about, with its name and its days
    /// as the style has them, or in the two-deadline style the days of each of the next two
    /// deadlines. A deadline's frame goes round once in the time from when its work started.
    static func frames(_ glance: MenuBarGlance, now: Date, style: AppSettings.MenuBarStyle) -> [Framed] {
        let countdowns = glance.upcoming.prefix(style == .stack ? stackCount : 1).map { next in
            let seconds = max(next.date.timeIntervalSince(now), 0)
            let urgency = Urgency(secondsLeft: seconds)
            let left = next.shareLeft(at: now, fallback: countdownScale)
            return Framed(
                loop: .time(from: ProgressFrame.share(1 - left), urgency: urgency),
                days: CountdownText.short(seconds), urgency: urgency)
        }
        if style == .stack, !countdowns.isEmpty {
            return countdowns
        }
        let urgency = countdowns.first?.urgency ?? .later
        let plan = glance.plan.flatMap { $0.blocks.isEmpty ? nil : PlanLoop($0, now: now) }
        let name = style == .iconOnly ? nil : (glance.plan?.name ?? glance.upcoming.first?.name).map(shortName)
        let showsDays = style == .days || (style == .bar && glance.plan != nil)
        return [
            Framed(
                loop: plan.map { .plan($0) } ?? countdowns.first?.loop ?? .time(from: 1, urgency: urgency),
                symbol: urgency == .critical ? "exclamationmark" : glance.plan?.symbol ?? "graduationcap.fill",
                name: name, days: showsDays && name != nil ? countdowns.first?.days : nil, urgency: urgency,
                setsDaysOff: style == .days)
        ]
    }

    /// The first word of the name, cut to fit: "NeurIPS 2026 Workshop" becomes "NeurIPS".
    static func shortName(_ name: String) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.count > maxNameLength ? String(first.prefix(maxNameLength - 1)) + "…" : first
    }

    static func spokenLabel(_ glance: MenuBarGlance, now: Date) -> String {
        var parts = ["DrBar"]
        if let plan = glance.plan {
            let done = PlanMath.progress(plan.blocks).formatted(.percent.precision(.fractionLength(0)))
            parts.append(plan.blocks.isEmpty ? plan.name : String(localized: "\(plan.name), \(done) of the plan done"))
            if plan.status == .behind || plan.status == .conflict {
                parts.append(plan.status.localizedDescription)
            }
        }
        parts += glance.upcoming.map { next in
            "\(next.name), \(next.deadline.name), \(CountdownText.spoken(next.date.timeIntervalSince(now)))"
        }
        return parts.joined(separator: "; ")
    }

    fileprivate struct LabelContent: View, Equatable {
        let frames: [Framed]
        /// What the calm color is made from, so that the image follows a change of accent color.
        let accent: NSColor?
        let increasesContrast: Bool

        var body: some View {
            HStack(spacing: 4) {
                ForEach(frames.indices, id: \.self) { index in
                    FramedView(framed: frames[index], increasesContrast: increasesContrast)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .frame(height: ProgressFrame.height)
            .padding(.horizontal, 1)
        }
    }
}

/// One frame of the menu bar item: what goes round it, and what it holds.
struct Framed: Equatable {
    var loop: ProgressFrame.Loop
    var symbol: String?
    var name: String?
    var days: String?
    /// How close its deadline is, which colors the days, and the symbol in the last three days.
    var urgency: Urgency
    /// Whether a dot sets the days off from the name, in the style that always has them.
    var setsDaysOff = false
}

private struct FramedView: View {
    let framed: Framed
    let increasesContrast: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let symbol = framed.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(framed.urgency == .critical ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            }
            if let name = framed.name {
                Text(verbatim: name)
            }
            if framed.setsDaysOff, framed.name != nil, framed.days != nil {
                Text(verbatim: "·")
            }
            if let days = framed.days {
                // Orange and red once few, as on the Conferences page.
                Text(verbatim: days)
                    .monospacedDigit()
                    .foregroundStyle(
                        framed.urgency == .critical || framed.urgency == .near
                            ? AnyShapeStyle(framed.urgency.color) : AnyShapeStyle(.primary))
            }
        }
        .fixedSize()
        // Clear of the outline all round.
        .padding(.horizontal, ProgressFrame.lineWidth + (framed.name == nil && framed.days == nil ? 3.5 : 4))
        .frame(minWidth: ProgressFrame.height, maxHeight: .infinity)
        .background(ProgressFrame(loop: framed.loop, increasesContrast: increasesContrast))
    }
}

/// A plan round the frame, from its first day to its deadline at the top, or to its last block
/// where that is later: where each block, today and the deadline fall, as shares of the way round.
struct PlanLoop: Equatable {
    struct Stretch: Equatable {
        let from: Double
        let to: Double
        let block: TimeBlock
    }

    let stretches: [Stretch]
    let today: Double?
    let deadline: Double?
    let status: PlanStatus

    init?(_ plan: MenuBarGlance.Plan, now: Date) {
        guard let first = plan.blocks.map({ $0.start.startDate() }).min(),
            let last = plan.blocks.map({ $0.end.endDate() }).max()
        else { return nil }
        let end = max(last, plan.deadline ?? last)
        let span = end.timeIntervalSince(first)
        guard span > 0 else { return nil }
        let share = { (date: Date) in ProgressFrame.share(date.timeIntervalSince(first) / span) }
        let blocks = plan.blocks.sorted { $0.start < $1.start }
        let spans = blocks.map { share($0.start.startDate())..<share($0.end.endDate()) }
        // The outline holds one block at a time: one that starts later takes the place of the one
        // it overlaps, rather than tinting it, and the earlier shows again where it outlasts it.
        stretches = zip(blocks, PlanMath.visibleParts(spans)).flatMap { block, parts in
            parts.map { Stretch(from: $0.lowerBound, to: $0.upperBound, block: block) }
        }
        // By the hour, so that the image is not drawn again every minute.
        let hour = Calendar.gregorianLocal.dateInterval(of: .hour, for: now)?.start ?? now
        today = (first...end).contains(hour) ? share(hour) : nil
        deadline = plan.deadline.map(share)
        status = plan.status
    }
}

/// The frame of the menu bar item: a rounded rectangle whose thick outline is a track that goes
/// round once, clockwise from the middle of its top edge, with what it shows on it.
struct ProgressFrame: View {
    enum Loop: Equatable {
        /// The time left until a deadline: from a place on the outline round to the top, in the
        /// color of how close it is.
        case time(from: Double, urgency: Urgency)
        case plan(PlanLoop)
    }

    let loop: Loop
    let increasesContrast: Bool

    static let height: CGFloat = 22
    static let lineWidth: CGFloat = 3.5

    /// A share of the way round, kept to 1/720, so that the frame is drawn again only when it
    /// visibly moves.
    nonisolated static func share(_ value: Double) -> Double {
        (min(max(value, 0), 1) * 720).rounded() / 720
    }

    var body: some View {
        Canvas { context, size in
            let width = Self.lineWidth
            let outline = Outline(
                in: CGRect(origin: .zero, size: size).insetBy(dx: width / 2, dy: width / 2),
                cornerRadius: Theme.cornerRadius(height: size.height) - width / 2)
            let round = StrokeStyle(lineWidth: width, lineCap: .round)
            let track = Color.primary.opacity(increasesContrast ? 0.3 : 0.16)
            context.stroke(outline.path, with: .color(track), lineWidth: width)
            switch loop {
            case let .time(from, urgency):
                if from < 1 {
                    let color = urgency == .later && increasesContrast ? Palette.calm : urgency.color
                    context.stroke(outline.part(from, 1), with: .color(color), style: round)
                }
            case let .plan(plan):
                // Each block's ends drawn in by its round cap and a little gap, so that blocks stay apart.
                let inset = Double((width / 2 + 0.6) / outline.length)
                for stretch in plan.stretches {
                    let color = BlockColor.color(for: stretch.block).opacity(stretch.block.isDone ? 1 : 0.4)
                    let from = stretch.from + inset
                    context.stroke(
                        outline.part(from, max(stretch.to - inset, from + 0.0005)), with: .color(color), style: round)
                }
                if let deadline = plan.deadline {
                    let point = outline.point(at: deadline)
                    let across = outline.across(at: deadline)
                    let reach = width / 2 + 0.5
                    let mark = Path { path in
                        path.move(to: CGPoint(x: point.x - across.dx * reach, y: point.y - across.dy * reach))
                        path.addLine(to: CGPoint(x: point.x + across.dx * reach, y: point.y + across.dy * reach))
                    }
                    context.stroke(mark, with: .color(.red), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
                if let today = plan.today {
                    // Today, a bead on the outline set off by a gap: orange while work is overdue, red
                    // when it runs past the deadline.
                    let point = outline.point(at: today)
                    func bead(_ radius: CGFloat) -> Path {
                        Path(ellipseIn: CGRect(origin: point, size: .zero).insetBy(dx: -radius, dy: -radius))
                    }
                    context.blendMode = .destinationOut
                    context.fill(bead(width / 2 + 1.2), with: .color(.black))
                    context.blendMode = .normal
                    let color: Color = plan.status == .conflict ? .red : plan.status == .behind ? .orange : .primary
                    context.fill(bead(width / 2 + 0.2), with: .color(color))
                }
            }
        }
    }
}

/// A rounded rectangle's outline as one path from the middle of its top edge, clockwise, so that a
/// share of the way round is a share of the path.
private struct Outline {
    let path: Path
    /// About how long it is, for gaps measured in points.
    let length: CGFloat

    init(in rect: CGRect, cornerRadius: CGFloat) {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        // SwiftUI starts the shape in the middle of a side and goes clockwise, so the top is a
        // whole number of quarters round from there.
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let quarter = [0.25, 0.5, 0.75, 1].min {
            Self.distance(shape.trimmedPath(from: 0, to: $0).currentPoint, top)
                < Self.distance(shape.trimmedPath(from: 0, to: $1).currentPoint, top)
        }
        let start = (quarter ?? 1).truncatingRemainder(dividingBy: 1)
        var path = shape.trimmedPath(from: start, to: 1)
        path.addPath(shape.trimmedPath(from: 0, to: start))
        self.path = path
        length = 2 * (rect.width + rect.height) - (8 - 2 * .pi) * cornerRadius
    }

    /// The outline from one share of the way round to another.
    func part(_ from: Double, _ to: Double) -> Path {
        path.trimmedPath(from: max(from, 0), to: min(to, 1))
    }

    func point(at share: Double) -> CGPoint {
        path.trimmedPath(from: 0, to: min(max(share, 0.001), 1)).currentPoint ?? .zero
    }

    /// The direction straight across the outline at `share`.
    func across(at share: Double) -> CGVector {
        let before = point(at: share - 0.004)
        let after = point(at: share + 0.004)
        let length = max(hypot(after.x - before.x, after.y - before.y), 0.001)
        return CGVector(dx: (before.y - after.y) / length, dy: (after.x - before.x) / length)
    }

    private static func distance(_ point: CGPoint?, _ other: CGPoint) -> CGFloat {
        point.map { hypot($0.x - other.x, $0.y - other.y) } ?? .infinity
    }
}

#if DEBUG
#Preview("Menu bar item") {
    DemoPreview {
        let store = AppStore.shared
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AppSettings.MenuBarStyle.allCases, id: \.self) { style in
                let glance = store.menuBarGlance(limit: style == .stack ? MenuBarLabel.stackCount : 1)
                Image(nsImage: MenuBarLabel.image(glance, now: store.now, style: style))
            }
        }
        .padding()
    }
}
#endif
