import AppKit
import DrBarKit
import SwiftUI

extension Animation {
    /// Along the axis: moving, zooming, going back to today, a new day, bars growing out of today,
    /// and work filling in as it is ticked off.
    public static let glide = Animation.smooth
    /// Rows and entries coming and going, and those around them closing up; what Undo and Esc put
    /// back.
    public static let settle = Animation.snappy(duration: 0.25)
    /// Rows stepping aside for one that is dragged.
    public static let makeRoom = Animation.snappy(duration: 0.2)
    /// A dragged row dropping into its place.
    public static let drop = Animation.snappy(duration: 0.15)
    /// A page coming in.
    public static let page = Animation.smooth(duration: 0.25)
}

/// Makes `change` with `animation`, or at once while the Mac is set to reduce motion: for changes
/// that come from outside any view, such as Undo, Esc or a menu command.
@MainActor
public func withMotion<Result>(_ animation: Animation, _ change: () throws -> Result) rethrows -> Result {
    try withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation, change)
}

extension AnyTransition {
    /// A page coming in: it fades in over the last few points of its way from `edge`, and the page
    /// it replaces goes at once, so that two pages are never drawn together.
    public static func page(from edge: HorizontalEdge? = nil) -> AnyTransition {
        let shift: CGFloat = edge == .leading ? -12 : edge == .trailing ? 12 : 0
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: shift)), removal: .identity)
    }
}

extension EnvironmentValues {
    /// How far the bars have grown out of today's line, from 0 to 1, while their timeline comes
    /// into view.
    @Entry var barGrowth: CGFloat = 1
}

#if DEBUG
extension EnvironmentValues {
    /// How far the bars have grown, given from outside, so that their growing can be drawn frame
    /// by frame for a recording.
    @Entry public var recordedGrowth: CGFloat?
}
#endif

extension View {
    /// The bars inside grow out of today's line as this view comes into view, all together, so
    /// that they can be compared all along; what marks a moment stays in its place.
    public func barsGrowIn() -> some View {
        modifier(BarsGrowIn())
    }
}

private struct BarsGrowIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @Environment(\.recordedGrowth) private var recordedGrowth
    #endif
    @State private var growth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.barGrowth, shownGrowth)
            .onAppear { withAnimation(.glide) { growth = 1 } }
            .onDisappear { growth = 0 }
    }

    private var shownGrowth: CGFloat {
        #if DEBUG
        if let recordedGrowth {
            return recordedGrowth
        }
        #endif
        return reduceMotion ? 1 : growth
    }
}

/// Where a bar is drawn while it grows: every point the same share of the way out from today's
/// line.
struct Growth {
    let today: CGFloat
    let share: CGFloat

    func callAsFunction(_ x: CGFloat) -> CGFloat {
        today + (x - today) * share
    }
}

/// What a view drawn from the axis interpolates while the axis moves: its length on a log scale and
/// where `now` stands on it, then how far it looks back.
public typealias AxisMotion = AnimatablePair<AnimatablePair<Double, Double>, Double>

extension TimeAxis {
    /// The axis as views drawn from it interpolate it. A zoom then goes at an even pace and keeps
    /// today steady, moving it is a straight slide, and every view, sharing `now`, moves as one;
    /// what has just passed widens or narrows with it.
    func animatableData(around now: Date) -> AxisMotion {
        let span = end.timeIntervalSince(start)
        return AnimatablePair(AnimatablePair(log(span), now.timeIntervalSince(start) / span), lookBack)
    }

    /// The axis that `animatableData(around:)` stands for.
    mutating func setAnimatableData(_ data: AxisMotion, around now: Date) {
        let span = exp(data.first.first)
        let start = now.addingTimeInterval(-data.first.second * span)
        self = TimeAxis(start: start, end: start.addingTimeInterval(span), lookBack: data.second)
    }
}
