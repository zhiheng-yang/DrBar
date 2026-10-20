import Foundation

extension Calendar {
    /// The Gregorian calendar in the current system time zone, with the user's first weekday.
    ///
    /// `Day` values are always Gregorian, whatever calendar the user picked in System Settings,
    /// so a stored plan never changes meaning.
    public static var gregorianLocal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    /// The Gregorian calendar in a fixed time zone. Tests and formatting use it.
    public static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// A calendar date without a time of day, such as the first or last day of a time block.
///
/// Time blocks are stored as days rather than instants, so a plan does not move when the
/// user travels to another time zone. In JSON a day is written as `"2026-11-16"`.
public struct Day: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

extension Day {
    /// The day that contains `date` in the calendar's time zone.
    public init(_ date: Date, calendar: Calendar = .gregorianLocal) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// The first moment of the day in the calendar's time zone.
    public func startDate(calendar: Calendar = .gregorianLocal) -> Date {
        calendar.startOfDay(for: noon(calendar: calendar))
    }

    /// The first moment of the following day, which is where a block that ends today stops.
    public func endDate(calendar: Calendar = .gregorianLocal) -> Date {
        adding(1, calendar: calendar).startDate(calendar: calendar)
    }

    public func adding(_ days: Int, calendar: Calendar = .gregorianLocal) -> Day {
        Day(calendar.date(byAdding: .day, value: days, to: noon(calendar: calendar))!, calendar: calendar)
    }

    /// The number of calendar days from this day to `other`; negative when `other` is earlier.
    public func days(to other: Day, calendar: Calendar = .gregorianLocal) -> Int {
        calendar.dateComponents([.day], from: noon(calendar: calendar), to: other.noon(calendar: calendar)).day!
    }

    /// Noon never falls into a daylight saving gap, so it is a safe anchor for day arithmetic.
    private func noon(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}

extension Day: Codable, CustomStringConvertible {
    /// The day as `yyyy-MM-dd`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Parses `yyyy-MM-dd`, rejecting days that do not exist such as `2026-02-30`.
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            DateComponents(year: year, month: month, day: day).isValidDate(in: Calendar(identifier: .gregorian))
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = Day(string: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a day such as 2026-11-16, found \(text)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
