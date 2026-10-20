import CoreGraphics
import Foundation

/// How a timeline looks at time: zoomed in or out around today, and moved back or ahead.
public struct AxisPosition: Equatable, Sendable {
    /// 1 shows the chosen range; 2 shows half as much time, each day twice as wide.
    public var zoom: Double
    /// Days the axis is moved; negative looks back.
    public var shift: Double

    /// How far a timeline looks back or ahead of its usual range: a year. However far it is
    /// zoomed out, it stays within that, so that it can never be moved away from everything.
    public static let shiftLimit = 366.0

    public init(zoom: Double = 1, shift: Double = 0) {
        self.zoom = zoom
        self.shift = shift
    }

    public func axis(now: Date, range: AxisRange, calendar: Calendar = .gregorianLocal) -> TimeAxis {
        TimeAxis(now: now, range: range, zoom: zoom, shiftedBy: shift, calendar: calendar)
    }

    /// Follows a swipe or a drag of `points` over a bar area `width` points wide: the bars move with
    /// the fingers.
    public mutating func pan(by points: CGFloat, width: CGFloat, now: Date, range: AxisRange) {
        let dayWidth = axis(now: now, range: range).dayWidth(in: width)
        guard points.isFinite, dayWidth.isFinite, dayWidth > 0 else { return }
        shift = clamped(shift - Double(points / dayWidth), now: now, range: range)
    }

    /// Zooms by `factor` around the point at `fraction` of the width, which keeps showing the same
    /// moment, as a map keeps the place under the fingers. A factor that is not a positive number
    /// changes nothing.
    public mutating func zoom(
        by factor: Double, at fraction: Double, now: Date, range: AxisRange, calendar: Calendar = .gregorianLocal
    ) {
        guard factor.isFinite, factor > 0 else { return }
        zoom(to: zoom * factor, at: fraction, now: now, range: range, calendar: calendar)
    }

    /// Zooms around today while it is on screen, otherwise around the middle.
    public mutating func zoom(by factor: Double, now: Date, range: AxisRange) {
        guard factor.isFinite, factor > 0 else { return }
        zoom(to: zoom * factor, now: now, range: range)
    }

    /// Zooms to `level` around today while it is on screen, otherwise around the middle: 1 for
    /// the chosen range.
    public mutating func zoom(to level: Double, now: Date, range: AxisRange) {
        let axis = axis(now: now, range: range)
        zoom(to: level, at: axis.contains(now) ? axis.fraction(now) : 0.5, now: now, range: range)
    }

    /// Zooms as `zoom(by:at:now:range:calendar:)` does, except that a pinch reaching the chosen
    /// range stops there, as a pinch in Keynote stops at 100 %, and goes on once it has gone a
    /// little further. `detent` carries that from one event of the pinch to the next. Returns
    /// whether the pinch has just come to a stop there.
    @discardableResult
    public mutating func pinch(
        by factor: Double, at fraction: Double, detent: inout ZoomDetent, now: Date, range: AxisRange,
        calendar: Calendar = .gregorianLocal
    ) -> Bool {
        guard factor.isFinite, factor > 0 else { return false }
        let hold = log(ZoomDetent.hold)
        if let pull = detent.pull.map({ $0 + log(factor) }) {
            guard abs(pull) > hold else {
                detent.pull = pull
                return false
            }
            detent.pull = nil
            zoom(by: exp(pull - (pull > 0 ? hold : -hold)), at: fraction, now: now, range: range, calendar: calendar)
            return false
        }
        let before = log(zoom)
        let after = before + log(factor)
        let isComing = abs(after) < abs(before) && abs(after) < log(ZoomDetent.reach)
        guard before != 0, isComing || (before < 0) != (after < 0) else {
            zoom(by: factor, at: fraction, now: now, range: range, calendar: calendar)
            return false
        }
        zoom(to: 1, at: fraction, now: now, range: range, calendar: calendar)
        detent.pull = 0
        return true
    }

    private mutating func zoom(
        to level: Double, at fraction: Double, now: Date, range: AxisRange, calendar: Calendar = .gregorianLocal
    ) {
        guard level.isFinite, level > 0 else { return }
        let fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0.5
        let before = axis(now: now, range: range, calendar: calendar)
        let anchor = before.start.addingTimeInterval(fraction * before.end.timeIntervalSince(before.start))
        let unzoomed = TimeAxis(now: now, range: range, calendar: calendar).days
        zoom = min(max(level, unzoomed / TimeAxis.visibleDays.upperBound), unzoomed / TimeAxis.visibleDays.lowerBound)
        let after = TimeAxis(now: now, range: range, zoom: zoom, calendar: calendar)
        let start = anchor.addingTimeInterval(-fraction * after.end.timeIntervalSince(after.start))
        shift = clamped(start.timeIntervalSince(after.start) / 86_400, now: now, range: range, calendar: calendar)
    }

    /// One step of ‹ or ›: a day while less than a week is on screen, otherwise a week, a month or
    /// three, as much as what is on screen allows: all but a day of a week, about a quarter of more.
    public mutating func step(_ direction: Int, now: Date, range: AxisRange) {
        let days = axis(now: now, range: range).days
        let step: Double = days < 7 ? 1 : days < 50 ? 7 : days < 300 ? 30 : 91
        shift = clamped(shift + Double(direction) * step, now: now, range: range)
    }

    /// The axis runs from `shift - back / zoom` to `shift + ahead / zoom` days from today, and
    /// either end may go a year past the usual range.
    private func clamped(_ shift: Double, now: Date, range: AxisRange, calendar: Calendar = .gregorianLocal) -> Double {
        let usual = TimeAxis(now: now, range: range, calendar: calendar)
        let back = usual.lookBack / 86_400
        let ahead = usual.days - back
        let lowest = back / zoom - back - Self.shiftLimit
        let highest = Self.shiftLimit + ahead - ahead / zoom
        return lowest <= highest ? min(max(shift, lowest), highest) : (lowest + highest) / 2
    }
}

/// Where a pinch stands with the chosen range: whether it has stopped there and how far it has
/// gone on since. One for each pinch, from its first event to its last.
public struct ZoomDetent: Equatable, Sendable {
    /// How near the chosen range a pinch coming towards it stops there, and how much further it
    /// then has to go to move on, as factors of the zoom.
    static let reach = 1.05
    static let hold = 1.12

    /// The pinch since it stopped, as the logarithm of its factor; `nil` while it is not held.
    var pull: Double?

    public init() {}
}
