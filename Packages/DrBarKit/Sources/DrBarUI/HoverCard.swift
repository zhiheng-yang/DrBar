import AppKit
import DrBarKit
import SwiftUI

/// More about what the pointer rests on than it shows itself: its name over a few quiet lines, as
/// Calendar sums up an event, with its dates lined up. It comes after a pause and moves on at once
/// to the next thing, goes with a click, a key or a scroll, and never takes the focus or a click.
public struct HoverCard: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        enum Tone: Sendable {
            case primary, secondary, tertiary
            /// Orange, as work that ended undone is edged.
            case warning
            /// Red, as for work that runs past its deadline.
            case alert
        }

        var text: String
        var tone: Tone
        /// An SF Symbol in front, as a to-do's circle.
        var symbol: String?

        init(_ text: String, tone: Tone = .secondary, symbol: String? = nil) {
            self.text = text
            self.tone = tone
            self.symbol = symbol
        }
    }

    /// One of several dates: what is due, when, and the time left. Done or passed, it steps back.
    struct DateLine: Equatable, Sendable {
        var name: String
        var date: String
        var state: String?
        var isClosed: Bool
    }

    /// Lines that belong together, a little apart from the others.
    enum Section: Equatable, Sendable {
        case lines([Line])
        case dates([DateLine])

        var isEmpty: Bool {
            switch self {
            case let .lines(lines): lines.isEmpty
            case let .dates(dates): dates.isEmpty
            }
        }
    }

    var title: String
    var sections: [Section]

    init(title: String, sections: [Section]) {
        self.title = title
        self.sections = sections.filter { !$0.isEmpty }
    }
}

/// The card of a view, if it has one, made only once the pointer rests on it. `id` tells the views
/// apart.
public struct HoverCardSource {
    public var id: String
    /// How far below the view the card keeps clear, as of the bar a milestone sits on.
    public var clearance: CGFloat
    public var make: () -> HoverCard?

    public init(id: String, clearance: CGFloat = 0, make: @escaping () -> HoverCard?) {
        self.id = id
        self.clearance = clearance
        self.make = make
    }
}

extension View {
    /// Shows the card that `card` makes once the pointer has rested on this view, or none where it
    /// has nothing to add. A host further up draws it, over everything inside the host.
    public func hoverCard(id: String, clearance: CGFloat = 0, card: @escaping () -> HoverCard?) -> some View {
        modifier(HoverCardTarget(source: HoverCardSource(id: id, clearance: clearance, make: card)))
    }

    public func hoverCard(_ source: HoverCardSource?) -> some View {
        modifier(HoverCardTarget(source: source))
    }

    /// Draws the hover cards of the views inside, over them.
    public func hoverCardHost() -> some View {
        overlayPreferenceValue(HoverCardRequest.Key.self) { request in
            HoverCardHost(request: request)
        }
    }

    /// No hover cards inside, as while an editor is open.
    public func hoverCardsDisabled(_ isDisabled: Bool = true) -> some View {
        environment(\.hoverCardsEnabled, !isDisabled)
    }
}

extension EnvironmentValues {
    @Entry var hoverCardsEnabled = true

    #if DEBUG
    /// The view whose card snapshots show, as if the pointer rested on it.
    @Entry public var hoverCardPreview: String?
    #endif
}

/// The card of the view under the pointer, and where that view and the pointer are.
struct HoverCardRequest {
    let id: String
    let anchor: Anchor<CGRect>
    let point: CGPoint
    let clearance: CGFloat
    let card: HoverCard

    struct Key: PreferenceKey {
        static var defaultValue: HoverCardRequest? { nil }

        static func reduce(value: inout HoverCardRequest?, nextValue: () -> HoverCardRequest?) {
            if let next = nextValue() {
                value = next
            }
        }
    }
}

private struct HoverCardTarget: ViewModifier {
    let source: HoverCardSource?

    @Environment(\.hoverCardsEnabled) private var isEnabled
    #if DEBUG
    @Environment(\.hoverCardPreview) private var preview
    #endif
    @State private var point: CGPoint?

    /// Where the pointer rests on the view, if it does.
    private var restingPoint: CGPoint? {
        #if DEBUG
        if let source, source.id == preview { return point ?? CGPoint(x: 24, y: 8) }
        #endif
        return point
    }

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case let .active(location):
                    // A pointer that moves a little has not moved on.
                    if let point, abs(point.x - location.x) + abs(point.y - location.y) < 4 { return }
                    point = location
                case .ended:
                    point = nil
                }
            }
            .anchorPreference(key: HoverCardRequest.Key.self, value: .bounds) { anchor in
                guard isEnabled, let point = restingPoint, let source, let card = source.make() else { return nil }
                return HoverCardRequest(
                    id: source.id, anchor: anchor, point: point, clearance: source.clearance, card: card)
            }
    }
}

/// Shows a card once the pointer has rested on a view for a moment, and at once while a card was just
/// showing, so that moving along a bar goes from block to block as tooltips do. A card stays where
/// it came up while the pointer moves over its view.
private struct HoverCardHost: View {
    let request: HoverCardRequest?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @Environment(\.hoverCardPreview) private var preview
    #endif
    @State private var shown: Rest?
    /// The view under the pointer.
    @State private var current: String?
    /// When the last card went, for showing the next one at once.
    @State private var hiddenAt: Date?
    /// The view whose card a click, key or scroll put away: none for it until the pointer leaves.
    @State private var dismissed: String?
    @State private var monitor = HoverCardMonitor()

    /// A view under the pointer, and where on it the pointer rests.
    struct Rest: Equatable {
        let id: String
        let point: CGPoint
    }

    var body: some View {
        let rest = request.map { Rest(id: $0.id, point: $0.point) }
        GeometryReader { geo in
            if let request, let shown, shown.id == request.id {
                let view = geo[request.anchor]
                let target = CGRect(
                    origin: view.origin, size: CGSize(width: view.width, height: view.height + request.clearance))
                HoverCardPlacement(target: target, x: view.minX + shown.point.x) {
                    HoverCardView(card: request.card)
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: rest) { await follow(rest) }
        .onAppear { monitor.start(dismiss: dismiss, release: release) }
        .onDisappear { monitor.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            dismiss()
        }
    }

    private func follow(_ rest: Rest?) async {
        current = rest?.id
        guard let rest else {
            // A moment's grace, so that crossing the gap between two blocks keeps the cards coming.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            if shown != nil {
                hiddenAt = .now
                shown = nil
            }
            // A view being dragged has no card for a while, but the pointer has not left it.
            if NSEvent.pressedMouseButtons == 0 {
                dismissed = nil
            }
            return
        }
        if dismissed != rest.id {
            dismissed = nil
        }
        guard shown?.id != rest.id else { return }
        #if DEBUG
        if rest.id == preview {
            shown = rest
            return
        }
        #endif
        let isWarm = shown != nil || hiddenAt.map { Date.now.timeIntervalSince($0) < 0.5 } == true
        if !isWarm {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
        }
        guard dismissed != rest.id, NSEvent.pressedMouseButtons == 0 else { return }
        withAnimation(isWarm || reduceMotion ? nil : .easeOut(duration: 0.12)) {
            shown = rest
        }
    }

    /// Once the button comes up, the view a click put away keeps its card away only while the
    /// pointer is still on it, as after dragging it.
    private func release() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if current != dismissed {
                dismissed = nil
            }
        }
    }

    private func dismiss() {
        dismissed = current
        shown = nil
        hiddenAt = nil
    }
}

/// Watches for what puts a card away, a click, a key, a scroll or a pinch, and for the button coming
/// up again. The event goes on to where it was going.
@MainActor
private final class HoverCardMonitor {
    private var monitor: Any?

    func start(dismiss: @escaping () -> Void, release: @escaping () -> Void) {
        stop()
        let events: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel, .magnify, .leftMouseUp,
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
            let isRelease = event.type == .leftMouseUp
            MainActor.assumeIsolated { isRelease ? release() : dismiss() }
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

/// Puts the card under the view it is about, from where the pointer was, or over it when there is
/// no room below, or else against the bottom, always inside. It is as wide as its lines, up to a
/// limit.
private struct HoverCardPlacement: Layout {
    let target: CGRect
    let x: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let width = min(card.sizeThatFits(.unspecified).width, HoverCardView.maxWidth)
        let size = card.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let margin: CGFloat = 8
        let gap: CGFloat = 6
        var y = target.maxY + gap
        if y + size.height > bounds.height - margin {
            let above = target.minY - gap - size.height
            y = above >= margin ? above : bounds.height - margin - size.height
        }
        let left = min(max(x - 16, margin), max(bounds.width - size.width - margin, margin))
        card.place(
            at: CGPoint(x: bounds.minX + left, y: bounds.minY + max(y, margin)), proposal: ProposedViewSize(size))
    }
}

/// The card itself, drawn as the system draws a popover, without the arrow.
struct HoverCardView: View {
    let card: HoverCard

    nonisolated static let maxWidth: CGFloat = 340

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(card.sections.enumerated()), id: \.offset) { _, section in
                    switch section {
                    case let .lines(lines): linesView(lines)
                    case let .dates(dates): datesView(dates)
                    }
                }
            }
            .font(.subheadline)
        }
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.08)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func linesView(_ lines: [HoverCard.Line]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let symbol = line.symbol {
                        Image(systemName: symbol)
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                    }
                    Text(line.text)
                        .foregroundStyle(style(line.tone))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The dates in columns, as the details view lists them: what, when, and the time left.
    private func datesView(_ dates: [HoverCard.DateLine]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 2) {
            ForEach(Array(dates.enumerated()), id: \.offset) { _, line in
                // Where the card is too narrow, the name is cut short, never the moment.
                GridRow {
                    Text(line.name)
                        .foregroundStyle(line.isClosed ? .tertiary : .secondary)
                        .lineLimit(1)
                    Text(line.date)
                        .foregroundStyle(line.isClosed ? .tertiary : .primary)
                        .fixedSize()
                    Text(line.state ?? "")
                        .foregroundStyle(line.isClosed ? .tertiary : .secondary)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }

    private func style(_ tone: HoverCard.Line.Tone) -> AnyShapeStyle {
        switch tone {
        case .primary: AnyShapeStyle(.primary)
        case .secondary: AnyShapeStyle(.secondary)
        case .tertiary: AnyShapeStyle(.tertiary)
        case .warning: AnyShapeStyle(Color.orange)
        case .alert: AnyShapeStyle(Color.red)
        }
    }
}
