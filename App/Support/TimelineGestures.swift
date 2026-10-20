import AppKit
import DrBarKit
import SwiftUI

extension View {
    /// Moves and zooms a timeline as a Mac moves and zooms a map: a sideways swipe or scroll moves
    /// it; pinching, or scrolling with ⌘ held, zooms around the pointer. Like a map, it follows the
    /// fingers as soon as the pointer is over it, before its window has been clicked. A pinch that
    /// comes to the chosen range stops there for a moment, with a light tap of the trackpad.
    /// `track` is the bar area in this view's coordinates. Vertical scrolling passes through, so a
    /// list under the view still scrolls.
    func timelineNavigation(
        _ position: Binding<AxisPosition>, track: CGRect, now: Date, range: AxisRange
    ) -> some View {
        modifier(TimelineNavigation(position: position, track: track, now: now, range: range))
    }

    /// Dragging across empty space moves the axis as well, for a mouse that cannot scroll
    /// sideways. Blocks and names keep their own drags.
    func dragToPan(perform action: @escaping (CGFloat) -> Void) -> some View {
        modifier(PanDrag(action: action))
    }
}

private struct TimelineNavigation: ViewModifier {
    @Binding var position: AxisPosition
    let track: CGRect
    let now: Date
    let range: AxisRange

    func body(content: Content) -> some View {
        content.background(
            GestureReader(
                pan: { position.pan(by: $0, width: track.width, now: now, range: range) },
                pinch: { factor, x, detent in
                    position.pinch(by: factor, at: fraction(x), detent: &detent, now: now, range: range)
                },
                zoom: { factor, x in position.zoom(by: factor, at: fraction(x), now: now, range: range) }))
    }

    private func fraction(_ x: CGFloat) -> Double {
        guard track.width > 0 else { return 0.5 }
        return min(max(Double((x - track.minX) / track.width), 0), 1)
    }
}

/// Watches the window's scroll and pinch events while the pointer is over the view, whether or not
/// the window is key; SwiftUI's own pinch waits for a click first. The view itself takes no
/// clicks, so everything above it works as before.
private struct GestureReader: NSViewRepresentable {
    let pan: (CGFloat) -> Void
    /// Zooms by the factor around the point, holding at the chosen range; true when it stops there.
    let pinch: (Double, CGFloat, inout ZoomDetent) -> Bool
    let zoom: (Double, CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView()
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.pan = pan
        view.pinch = pinch
        view.zoom = zoom
    }

    final class ReaderView: NSView {
        var pan: ((CGFloat) -> Void)?
        var pinch: ((Double, CGFloat, inout ZoomDetent) -> Bool)?
        var zoom: ((Double, CGFloat) -> Void)?
        private var monitor: Any?
        private var isHorizontal: Bool?
        private var detent = ZoomDetent()

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self else { return event }
                let isTaken: Bool
                if event.type == .magnify {
                    let pinch = Pinch(event)
                    isTaken = MainActor.assumeIsolated { self.take(pinch) }
                } else {
                    let scroll = Scroll(event)
                    isTaken = MainActor.assumeIsolated { self.take(scroll) }
                }
                return isTaken ? nil : event
            }
        }

        /// Where an event in the window numbered `windowNumber` happens in this view, if it is over it.
        private func point(at location: CGPoint, inWindow windowNumber: Int) -> CGPoint? {
            guard let window, windowNumber == window.windowNumber, !isHiddenOrHasHiddenAncestor else { return nil }
            let point = convert(location, from: nil)
            return bounds.contains(point) ? point : nil
        }

        private func take(_ pinch: Pinch) -> Bool {
            guard let point = point(at: pinch.location, inWindow: pinch.windowNumber) else { return false }
            if pinch.begins {
                detent = ZoomDetent()
            }
            if pinch.factor != 1, self.pinch?(pinch.factor, point.x, &detent) == true {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            return true
        }

        /// Whether the scroll moves or zooms the axis rather than whatever is under the pointer.
        private func take(_ scroll: Scroll) -> Bool {
            guard let point = point(at: scroll.location, inWindow: scroll.windowNumber) else { return false }
            if scroll.withCommand, abs(scroll.upward) > abs(scroll.dx) {
                // Up zooms in, as on a map.
                zoom?(exp(Double(scroll.upward) * 0.01), point.x)
                return true
            }
            if scroll.startsGesture {
                isHorizontal = nil
            }
            if isHorizontal == nil, scroll.dx != 0 || scroll.dy != 0 {
                isHorizontal = abs(scroll.dx) > abs(scroll.dy)
            }
            guard isHorizontal == true else { return false }
            pan?(scroll.dx)
            return true
        }
    }

    /// What matters of a pinch event.
    struct Pinch: Sendable {
        let windowNumber: Int
        let location: CGPoint
        /// How much the pinch has grown since the last event: 1.1 is a tenth larger.
        let factor: Double
        let begins: Bool

        init(_ event: NSEvent) {
            windowNumber = event.windowNumber
            location = event.locationInWindow
            factor = 1 + Double(event.magnification)
            begins = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        }
    }

    /// What matters of a scroll event.
    struct Scroll: Sendable {
        let windowNumber: Int
        let location: CGPoint
        /// In points: a mouse wheel counts in lines.
        let dx: CGFloat
        let dy: CGFloat
        /// How far the fingers or the wheel went up, whichever way the user's scrolling runs.
        let upward: CGFloat
        let withCommand: Bool
        /// A mouse wheel step, or the first event of a trackpad gesture. Momentum after the fingers
        /// lift continues the gesture.
        let startsGesture: Bool

        init(_ event: NSEvent) {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            windowNumber = event.windowNumber
            location = event.locationInWindow
            dx = event.scrollingDeltaX * scale
            dy = event.scrollingDeltaY * scale
            upward = event.isDirectionInvertedFromDevice ? -dy : dy
            withCommand = event.modifierFlags.contains(.command)
            let isWheel = event.phase.isEmpty && event.momentumPhase.isEmpty
            startsGesture = isWheel || event.phase.contains(.began) || event.phase.contains(.mayBegin)
        }
    }
}

private struct PanDrag: ViewModifier {
    let action: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    NSCursor.closedHand.set()
                    action(value.translation.width - (lastTranslation ?? 0))
                    lastTranslation = value.translation.width
                }
                .onEnded { _ in
                    lastTranslation = nil
                    NSCursor.arrow.set()
                })
    }
}
