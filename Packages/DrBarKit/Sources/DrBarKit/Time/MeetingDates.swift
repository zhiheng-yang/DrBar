import Foundation

/// When a conference takes place, read from ccfddl's free text such as `June 20-25, 2027`,
/// `June 30 - July 3, 2026` or `April 29, 2025`.
///
/// Anything else (`TBD`, `May 2027 (exact dates TBD)`, several venues) is not guessed at: the
/// text is still shown as written, but no dates are drawn.
public struct MeetingDates: Codable, Hashable, Sendable {
    public var start: Day
    /// The last day (inclusive).
    public var end: Day

    public init(start: Day, end: Day) {
        self.start = start
        self.end = end
    }

    public init?(parsing text: String) {
        let pattern =
            /(?i)\s*([a-z]{3,9})\.?\s+(\d{1,2})(?:\s*[-–]\s*(?:([a-z]{3,9})\.?\s+)?(\d{1,2}))?\s*,?\s+(\d{4})\s*/
        guard let match = text.wholeMatch(of: pattern),
            let startMonth = Self.month(match.1), let startDay = Int(match.2), let year = Int(match.5)
        else { return nil }
        let endMonth = match.3.map { Self.month($0) } ?? startMonth
        guard let endMonth else { return nil }
        let endDay = match.4.flatMap { Int($0) } ?? startDay
        guard let start = Day(string: Self.iso(year, startMonth, startDay)),
            let end = Day(string: Self.iso(year, endMonth, endDay)), start <= end
        else { return nil }
        self.init(start: start, end: end)
    }

    private static let months = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]

    /// `June`, `Jun` or `Sept` → 6 or 9; `nil` for anything that is not an English month name.
    private static func month(_ name: Substring) -> Int? {
        let lower = name.lowercased()
        let index = months.firstIndex { full in
            full == lower || (lower.count == 3 && full.hasPrefix(lower)) || (lower == "sept" && full == "september")
        }
        return index.map { $0 + 1 }
    }

    private static func iso(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension ConferenceEdition {
    /// The flags of the countries of its whole place, which the short one leaves out.
    public var flags: String {
        place?.announcedText.map(CountryFlags.flags(in:)) ?? ""
    }

    /// The city part of the place, for a compact row: `Seattle, WA, United States` → `Seattle`.
    public var shortPlace: String? {
        guard let place = place?.announcedText else { return nil }
        // Without what is in brackets: `Vienna (hybrid)` → `Vienna`. Read by hand, as it is for every
        // edition of every conference.
        var city = ""
        var depth = 0
        for character in place.prefix(while: { $0 != "," }) {
            switch character {
            case "(":
                while city.last?.isWhitespace == true { city.removeLast() }
                depth += 1
            case ")" where depth > 0:
                depth -= 1
            default:
                if depth == 0 { city.append(character) }
            }
        }
        city = city.trimmingCharacters(in: .whitespaces)
        // Some entries are written in capitals.
        return city == city.uppercased() && city.count > 3 ? city.capitalized : city
    }
}
