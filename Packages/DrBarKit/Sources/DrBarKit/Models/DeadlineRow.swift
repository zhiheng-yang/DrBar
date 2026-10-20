import Foundation

/// One row of a deadline list: the abstract and paper deadlines of one round of a conference.
///
/// Shared by the deadline lists, the menu bar and reminders.
public struct DeadlineRow: Hashable, Sendable, Identifiable {
    public enum Source: Codable, Hashable, Sendable {
        case conference(series: String, edition: String, round: String)

        public var series: String {
            switch self {
            case let .conference(series, _, _): series
            }
        }

        public var edition: String {
            switch self {
            case let .conference(_, edition, _): edition
            }
        }

        public var round: String {
            switch self {
            case let .conference(_, _, round): round
            }
        }

        /// What the rows of a round, and what is followed of it, know it by, e.g. `cvpr27|#1`.
        public var id: String {
            "\(edition)|\(round)"
        }
    }

    public enum State: Sendable {
        case scheduled
        /// The deadline is `TBD` in ccfddl. Shown last, with no bar.
        case notAnnounced
        /// A date is given but cannot be read, usually because its time zone is not one the app
        /// knows. Shown as written, with no bar, and never used for reminders.
        case unreadable
    }

    public var id: String
    public var source: Source
    /// The series title, `CVPR`.
    public var name: String
    public var year: Int?
    /// Tells rounds of one edition apart; `nil` for single-round editions.
    public var roundLabel: String?
    public var abstractDate: Date?
    public var paperDate: Date?
    /// What follows the submission, drawn faintly after the bar.
    public var rebuttalDate: Date?
    public var decisionDate: Date?
    public var meeting: MeetingDates?
    /// Where the conference takes place, shortened to the city.
    public var place: String?
    /// The flags of the countries of the whole place.
    public var flags: String
    public var state: State
    /// The time zone as the source writes it, e.g. `UTC-12`.
    public var timeZone: String
    /// The raw deadline text of an `.unreadable` row.
    public var rawDeadline: String?

    public init(
        id: String, source: Source, name: String, year: Int?, roundLabel: String?, abstractDate: Date?,
        paperDate: Date?, rebuttalDate: Date? = nil, decisionDate: Date? = nil,
        meeting: MeetingDates? = nil, place: String? = nil, flags: String = "", state: State, timeZone: String,
        rawDeadline: String? = nil
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.year = year
        self.roundLabel = roundLabel
        self.abstractDate = abstractDate
        self.paperDate = paperDate
        self.rebuttalDate = rebuttalDate
        self.decisionDate = decisionDate
        self.meeting = meeting
        self.place = place
        self.flags = flags
        self.state = state
        self.timeZone = timeZone
        self.rawDeadline = rawDeadline
    }

    /// "CVPR 2027".
    public var title: String {
        year.map { "\(name) \(String($0))" } ?? name
    }

    /// "SIGMOD 2027 round 4", or "CVPR 2027" for an edition of one round.
    public var fullTitle: String {
        [title, roundLabel].compactMap { $0 }.joined(separator: " ")
    }

    /// Where the bar ends: the paper deadline, or the abstract deadline when only that is known.
    public var endDate: Date? {
        paperDate ?? abstractDate
    }

    public var seriesKey: String {
        source.series
    }

    /// The id that the date of `kind` of this row has in reminders and ticks, as a `DeadlineItem`
    /// has it.
    public func id(of kind: DeadlineKind) -> String {
        DeadlineItem.id(edition: source.edition, kind: kind, round: source.round)
    }

    /// The abstract deadline while it is still ahead.
    func upcomingAbstract(now: Date) -> Date? {
        abstractDate.flatMap { $0 > now ? $0 : nil }
    }

    /// The next deadline of this row after `now`: the abstract deadline first, then the paper deadline.
    public func nextDeadline(after now: Date) -> (date: Date, kind: DeadlineKind)? {
        if let abstract = upcomingAbstract(now: now) {
            return (abstract, .abstract)
        }
        if let paper = paperDate, paper > now {
            return (paper, .paper)
        }
        return nil
    }
}
