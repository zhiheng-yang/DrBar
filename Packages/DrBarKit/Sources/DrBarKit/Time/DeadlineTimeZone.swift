import Foundation

/// The time zone notations that deadlines are written in.
///
/// ccfddl uses `AoE`, `UTC`, `UTC±N` and `PT`. Custom deadlines may also use an IANA identifier
/// such as `Europe/Amsterdam`, which is what "local time" is stored as.
public enum DeadlineTimeZone {
    /// Anywhere on Earth: the last time zone where the day is still the given date (UTC−12).
    public static let anywhereOnEarth = TimeZone(secondsFromGMT: -12 * 3600)!

    /// Resolves a ccfddl time zone. Returns `nil` for anything else, which the app shows as
    /// "unrecognized time zone" and never uses for bars or reminders.
    public static func ccf(_ raw: String) -> TimeZone? {
        let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch text {
        case "AOE": return anywhereOnEarth
        case "UTC", "GMT", "Z": return TimeZone(secondsFromGMT: 0)
        case "PT": return TimeZone(identifier: "America/Los_Angeles")
        default: break
        }
        guard let match = text.wholeMatch(of: /(?:UTC|GMT)([+-])(\d{1,2})(?::(\d{2}))?/),
            let hours = Int(match.2), hours <= 14
        else { return nil }
        let minutes = match.3.flatMap { Int($0) } ?? 0
        guard minutes < 60 else { return nil }
        let sign = match.1 == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }

    /// Resolves the time zone of a custom deadline: a ccfddl notation or an IANA identifier.
    public static func custom(_ raw: String) -> TimeZone? {
        ccf(raw) ?? TimeZone(identifier: raw)
    }

    /// The time zone as a deadline is written with it: ccfddl's notation as it is, and local time
    /// as its offset from UTC on `date`, "UTC+2", which reads the same in every language.
    public static func notation(_ raw: String, at date: Date) -> String {
        guard ccf(raw) == nil, let zone = TimeZone(identifier: raw) else { return raw }
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "UTC" }
        let minutes = abs(seconds) / 60 % 60
        return "UTC\(seconds < 0 ? "-" : "+")\(abs(seconds) / 3600)"
            + (minutes == 0 ? "" : String(format: ":%02d", minutes))
    }

    /// `date` moved by `days` whole days of the time zone `raw`, keeping its time of day there.
    public static func moving(_ date: Date, byDays days: Int, in raw: String) -> Date {
        let calendar = Calendar.gregorian(in: custom(raw) ?? .current)
        return calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// The fixed choices offered when entering a custom deadline, besides local time.
    public static let customChoices: [String] =
        ["AoE", "UTC"] + (-12...14).filter { $0 != 0 }.map { $0 < 0 ? "UTC\($0)" : "UTC+\($0)" } + ["PT"]
}
