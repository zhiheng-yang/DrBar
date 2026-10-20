import Foundation

/// A day in a paper's plan that something is due by, set by the user: an internal deadline, a
/// draft for the supervisor, a meeting.
public struct Milestone: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var day: Day
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String = "", day: Day, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.day = day
        self.isDone = isDone
    }

    /// Not done, and its day is over.
    public func isOverdue(today: Day) -> Bool {
        !isDone && day < today
    }

    /// Where it is drawn: the middle of its day.
    public func date(calendar: Calendar = .gregorianLocal) -> Date {
        let start = day.startDate(calendar: calendar)
        return start.addingTimeInterval(day.endDate(calendar: calendar).timeIntervalSince(start) / 2)
    }

    public func moved(by days: Int) -> Milestone {
        var milestone = self
        milestone.day = day.adding(days)
        return milestone
    }

    enum CodingKeys: String, CodingKey {
        case id, title, day, isDone
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        title = c(.title, default: "")
        day = try c.required(.day)
        isDone = c(.isDone, default: false)
    }
}
