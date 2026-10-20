import CoreGraphics
import Foundation

/// The time axis that every bar shares: the last few days, then a week or 1, 3 or 6 months from
/// today. It can be zoomed in or out around today, and moved earlier or later, to look closer,
/// further, back or ahead.
///
/// All rows of one list must use the same axis, so their bar lengths can be compared.
public struct TimeAxis: Equatable, Sendable {
    /// However far it is zoomed, the axis shows between three days and two years.
    public static let visibleDays: ClosedRange<Double> = 3...730

    public let start: Date
    public let end: Date
    /// The part before today when the axis is not moved, where what has just passed is drawn faint.
    public let lookBack: TimeInterval

    /// `zoom` shows that many times less time around today, each day that much wider; `shift`
    /// moves the axis by that many days. Both take fractions, so they can follow the fingers.
    public init(
        now: Date, range: AxisRange, zoom: Double = 1, shiftedBy shift: Double = 0,
        calendar: Calendar = .gregorianLocal
    ) {
        let today = calendar.startOfDay(for: now)
        let back = today.timeIntervalSince(calendar.date(byAdding: .day, value: -range.recentDays, to: today)!)
        let ahead = calendar.date(byAdding: range.length, to: today)!.timeIntervalSince(today)
        let offset = shift * 86_400
        self.init(
            start: today.addingTimeInterval(offset - back / zoom), end: today.addingTimeInterval(offset + ahead / zoom),
            lookBack: back / zoom)
    }

    /// An axis from one moment to another, such as one that an animation passes through.
    public init(start: Date, end: Date, lookBack: TimeInterval) {
        self.start = start
        self.end = end
        self.lookBack = lookBack
    }

    /// How many days the axis shows.
    public var days: Double {
        end.timeIntervalSince(start) / 86_400
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date <= end
    }

    /// The position of `date` as a fraction of the axis: 0 at the left end, 1 at the right end.
    public func fraction(_ date: Date) -> Double {
        date.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    /// The horizontal position of `date` in a bar area `width` points wide, clamped to the ends.
    public func x(_ date: Date, width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(fraction(date), 0), 1))
    }

    /// The moment at `x` in a bar area `width` points wide, the other way round from `x(_:width:)`.
    public func date(atX x: CGFloat, width: CGFloat) -> Date {
        start.addingTimeInterval(end.timeIntervalSince(start) * Double(x / max(width, 1)))
    }

    /// How wide one day is in a bar area `width` points wide.
    public func dayWidth(in width: CGFloat) -> CGFloat {
        width / CGFloat(days)
    }

    /// The steps an axis is divided into, from fine to coarse.
    public enum Unit: Sendable {
        case day, week, month, quarter
    }

    /// Where each `unit` begins on the axis: every midnight, the first day of each week as the
    /// user's calendar has it, the first of each month, or the first of January, April, July and
    /// October.
    public func ticks(_ unit: Unit, calendar: Calendar = .gregorianLocal) -> [Date] {
        switch unit {
        case .day:
            dates(matching: DateComponents(hour: 0), calendar)
        case .week:
            dates(matching: DateComponents(weekday: calendar.firstWeekday), calendar)
        case .month:
            dates(matching: DateComponents(day: 1), calendar)
        case .quarter:
            dates(matching: DateComponents(day: 1), calendar).filter {
                calendar.component(.month, from: $0) % 3 == 1
            }
        }
    }

    /// Every day the axis shows, whole or in part, from its first moment to the next day's.
    public func dayIntervals(calendar: Calendar = .gregorianLocal) -> [DateInterval] {
        var days: [DateInterval] = []
        var day = Day(start, calendar: calendar)
        while day.startDate(calendar: calendar) < end {
            days.append(DateInterval(start: day.startDate(calendar: calendar), end: day.endDate(calendar: calendar)))
            day = day.adding(1, calendar: calendar)
        }
        return days
    }

    /// The weekends on the axis as the calendar's region keeps them: Saturday and Sunday in most
    /// places, Friday and Saturday in some.
    public func weekends(calendar: Calendar = .gregorianLocal) -> [DateInterval] {
        var weekends: [DateInterval] = []
        // A week before, for a weekend that the axis starts in.
        var after = start.addingTimeInterval(-7 * 86_400)
        while let weekend = calendar.nextWeekend(startingAfter: after), weekend.start < end {
            if weekend.end > start {
                weekends.append(weekend)
            }
            after = weekend.end
        }
        return weekends
    }

    /// Every `days` days from `origin`, back and ahead, as far as the axis goes: the lines of an
    /// axis labelled with the days from today.
    public func ticks(every days: Int, from origin: Date, calendar: Calendar = .gregorianLocal) -> [Date] {
        guard days > 0 else { return [] }
        let span = Double(days) * 86_400
        let first = Int((start.timeIntervalSince(origin) / span).rounded(.down)) - 1
        let last = Int((end.timeIntervalSince(origin) / span).rounded(.up)) + 1
        return (first...last)
            .compactMap { calendar.date(byAdding: .day, value: $0 * days, to: origin) }
            .filter { $0 > start && $0 <= end }
    }

    private func dates(matching match: DateComponents, _ calendar: Calendar) -> [Date] {
        var result: [Date] = []
        calendar.enumerateDates(startingAfter: start, matching: match, matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date <= end else {
                stop = true
                return
            }
            result.append(date)
        }
        return result
    }
}
