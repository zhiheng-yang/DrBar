import DrBarKit
import Foundation
import Yams

/// Turns ccfddl's YAML into a `ConferenceCatalog`.
public enum DeadlineParser {
    /// The result of parsing `allconf.yml`.
    public struct Parsed: Sendable {
        public var catalog: ConferenceCatalog
        /// Series found in the file with a date this version can read in any edition, before old
        /// editions were dropped. Used to reject a download that suddenly lists far fewer
        /// conferences than before, or whose editions or dates this version cannot read.
        public var seriesCount: Int
    }

    /// Parses `allconf.yml`. Throws only when the file as a whole is not a list of conferences;
    /// single malformed entries are skipped.
    ///
    /// Editions older than last year are left out: they are never shown, and dropping them keeps
    /// `deadlines.json` and memory small. Each kept edition remembers the previous edition's paper
    /// deadline for the "for reference" line.
    public static func parse(yaml: String, now: Date) throws -> Parsed {
        let entries = try YAMLDecoder().decode([Lenient<CCFSeries>].self, from: yaml)
        let series = entries.compactMap(\.value)
        let firstYear = Calendar.gregorian(in: .gmt).component(.year, from: now) - 1
        let dated = series.filter { $0.editions.contains(where: hasReadableDate) }
        return Parsed(catalog: catalog(from: series, firstYear: firstYear), seriesCount: dated.count)
    }

    /// Whether any round of `edition` has a paper or abstract deadline this version can read.
    static func hasReadableDate(_ edition: CCFSeries.Edition) -> Bool {
        guard let zone = DeadlineTimeZone.ccf(edition.timeZoneText) else { return false }
        return edition.timeline.contains { round in
            [round.deadline, round.abstractDeadline].contains { $0.flatMap { date(from: $0, in: zone) } != nil }
        }
    }

    public static func parse(yaml data: Data, now: Date) throws -> Parsed {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "allconf.yml is not UTF-8"))
        }
        return try parse(yaml: text, now: now)
    }

    /// Parses `allacc.yml`, the acceptance rates. Throws only when the file as a whole is not a
    /// list of conferences; single malformed entries are skipped.
    public static func parseAcceptance(yaml data: Data) throws -> [AcceptanceRates] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "allacc.yml is not UTF-8"))
        }
        let entries = try YAMLDecoder().decode([Lenient<CCFAcceptance>].self, from: text)
        return entries.compactMap(\.value).filter { !$0.years.isEmpty }.map { entry in
            AcceptanceRates(
                seriesKey: entry.conferenceKey?.trimmingCharacters(in: .whitespaces).nilIfEmpty, title: entry.title,
                years: entry.years.map {
                    AcceptanceRate(year: $0.year, rate: $0.rate, submitted: $0.submitted, accepted: $0.accepted)
                })
        }
    }

    /// `2026-11-16 23:59:59` in `zone` as an instant. `nil` for `TBD`, empty text or anything
    /// malformed, including impossible dates such as `2026-02-30`.
    ///
    /// A date without a time means the end of that day, as in ccfddl's own convention.
    static func date(from text: String, in zone: TimeZone) -> Date? {
        let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
        guard (1...2).contains(pieces.count), let day = Day(string: String(pieces[0])) else { return nil }
        var hour = 23, minute = 59, second = 59
        if pieces.count == 2 {
            let fields = pieces[1].split(separator: ":", omittingEmptySubsequences: false)
            let clock = fields.compactMap { Int($0) }
            guard (2...3).contains(clock.count), clock.count == fields.count else { return nil }
            hour = clock[0]
            minute = clock[1]
            second = clock.count == 3 ? clock[2] : 0
            guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        }
        let calendar = Calendar.gregorian(in: zone)
        let parts = DateComponents(
            year: day.year, month: day.month, day: day.day, hour: hour, minute: minute, second: second)
        guard parts.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: parts)
    }

    static func catalog(from entries: [CCFSeries], firstYear: Int) -> ConferenceCatalog {
        var result: [ConferenceSeries] = []
        for entry in entries {
            let key =
                entry.conferenceKey?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                ?? "\(entry.sub)/\(entry.title.lowercased())"
            var editions: [ConferenceEdition] = []
            var previous: PreviousEdition?

            for e in entry.editions.sorted(by: { $0.year < $1.year }) {
                if e.year >= firstYear {
                    editions.append(
                        ConferenceEdition(
                            id: e.id, year: e.year, link: e.link ?? "", timeZone: e.timeZoneText,
                            date: e.date, place: e.place, meeting: e.date.flatMap(MeetingDates.init(parsing:)),
                            rounds: rounds(e.timeline, timeZone: DeadlineTimeZone.ccf(e.timeZoneText)),
                            previous: previous))
                }
                if let deadline = e.timeline.lazy.compactMap(\.deadline).first(where: {
                    DeadlineValue(raw: $0, date: nil).isAnnounced
                }) {
                    previous = PreviousEdition(year: e.year, paperDeadline: deadline)
                }
            }
            guard !editions.isEmpty else { continue }
            result.append(
                ConferenceSeries(
                    id: key, title: entry.title, description: entry.description ?? "", category: entry.sub,
                    ccfRank: entry.rank?.ccf, coreRank: entry.rank?.core, thcplRank: entry.rank?.thcpl,
                    dblp: entry.dblp?.trimmingCharacters(in: .whitespaces).nilIfEmpty, editions: editions))
        }
        result.sort { $0.id < $1.id }
        return ConferenceCatalog(series: result)
    }

    /// Round ids come from comments, so they stay stable when ccfddl inserts a round; rounds
    /// without a comment, and repeated comments, fall back to their position.
    static func rounds(_ timeline: [CCFSeries.Round], timeZone: TimeZone?) -> [ConferenceRound] {
        let comments = timeline.map { $0.comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        let counts = Dictionary(comments.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)

        return timeline.enumerated().map { index, round in
            let comment = comments[index]
            let id: String
            switch comment {
            case let comment? where counts[comment] == 1: id = comment
            case let comment?: id = "\(comment) #\(index + 1)"
            case nil: id = "#\(index + 1)"
            }
            func value(_ text: String?) -> DeadlineValue? {
                guard let text = text?.trimmingCharacters(in: .whitespaces).nilIfEmpty else { return nil }
                return DeadlineValue(raw: text, date: timeZone.flatMap { date(from: text, in: $0) })
            }
            return ConferenceRound(
                id: id, index: index, comment: comment,
                abstract: value(round.abstractDeadline), paper: value(round.deadline),
                rebuttal: value(round.rebuttalDeadline), decision: value(round.decisionDeadline))
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
