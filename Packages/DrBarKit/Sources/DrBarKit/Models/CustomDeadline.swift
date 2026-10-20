import Foundation

/// A deadline that ccfddl does not list, of a paper's or an item's own: supplementary material, a
/// camera-ready version, a workshop, a journal's special issue, the letters of an application.
public struct CustomDeadline: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// The deadline as an absolute instant.
    public var date: Date
    /// The time zone the deadline was entered in: a ccfddl notation (`AoE`, `UTC+8`, `PT`…) or an
    /// IANA identifier for local time. Used to show the deadline as the organizers wrote it.
    public var timeZone: String
    public var link: String
    public var note: String
    /// Ticked off, such as letters that were sent.
    public var isDone: Bool

    public init(
        id: UUID = UUID(), title: String, date: Date, timeZone: String = "AoE", link: String = "", note: String = "",
        isDone: Bool = false
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.timeZone = timeZone
        self.link = link
        self.note = note
        self.isDone = isDone
    }

    enum CodingKeys: String, CodingKey {
        case id, title, date, timeZone, link, note, isDone
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        title = c(.title, default: "")
        date = try c.required(.date)
        timeZone = c(.timeZone, default: "AoE")
        link = c(.link, default: "")
        note = c(.note, default: "")
        isDone = c(.isDone, default: false)
    }

    /// The same time of day in its own time zone, `days` later, also across a change of daylight
    /// saving time.
    public func moved(byDays days: Int) -> CustomDeadline {
        var moved = self
        moved.date = DeadlineTimeZone.moving(date, byDays: days, in: timeZone)
        return moved
    }
}

/// A deadline as earlier builds kept it, in one list with the paper it belongs to, or, before
/// that, with none.
struct StoredDeadline: Decodable {
    var deadline: CustomDeadline
    var paperID: UUID?

    enum CodingKeys: String, CodingKey {
        case paperID
    }

    init(from decoder: any Decoder) throws {
        deadline = try CustomDeadline(from: decoder)
        paperID = try LenientContainer(decoder, keyedBy: CodingKeys.self)(.paperID, default: nil)
    }
}

extension UserData {
    /// Adds a deadline of its own to a paper or an item. One without a conference that aims at
    /// none then aims at the one `ownDeadlineToAimAt` picks: the next ahead, or else the last; for
    /// a paper already submitted, the last that has passed, the one it went in by.
    public mutating func addDeadline(_ deadline: CustomDeadline, to paperID: UUID, now: Date) {
        guard let p = papers.firstIndex(where: { $0.id == paperID }) else { return }
        papers[p].deadlines.append(deadline)
        if papers[p].target == nil, !papers[p].deadlines.contains(where: { $0.id == papers[p].mainDeadline }) {
            papers[p].mainDeadline = papers[p].ownDeadlineToAimAt(now: now)
        }
    }

    public mutating func makeMainDeadline(_ id: UUID, of paperID: UUID) {
        guard let p = papers.firstIndex(where: { $0.id == paperID }),
            papers[p].deadlines.contains(where: { $0.id == id })
        else { return }
        papers[p].mainDeadline = id
    }

    /// Ticks a deadline off, or back on: one of its own, or one of its conference's dates.
    public mutating func setDone(_ isDone: Bool, of deadline: PaperDeadline, in paperID: UUID) {
        guard let p = papers.firstIndex(where: { $0.id == paperID }) else { return }
        if let id = deadline.ownID, let index = papers[p].deadlines.firstIndex(where: { $0.id == id }) {
            papers[p].deadlines[index].isDone = isDone
        } else if deadline.kind != nil {
            var ticks = Set(papers[p].doneDeadlines)
            if isDone {
                ticks.insert(deadline.id)
            } else {
                ticks.remove(deadline.id)
            }
            // In order, so that the file stays the same from one save to the next.
            papers[p].doneDeadlines = ticks.sorted()
        }
    }
}

extension Paper {
    /// The own deadline to aim at once there is no other: the next one ahead, or else the last. A
    /// paper already submitted went in by one that has passed, the last of them, if any.
    func ownDeadlineToAimAt(now: Date) -> UUID? {
        let ordered = deadlines.sorted { $0.date < $1.date }
        if isPaper, stage.isSubmitted {
            return ordered.last { $0.date <= now }?.id
        }
        return (ordered.first { $0.date > now } ?? ordered.last)?.id
    }
}
