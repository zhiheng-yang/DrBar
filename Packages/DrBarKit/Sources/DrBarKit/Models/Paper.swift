import Foundation

/// A paper the user is working on, with the conference it goes to, its deadlines and its plan; or,
/// with a `groupID`, another piece of work with deadlines that is planned the same way, such as an
/// application.
public struct Paper: Codable, Identifiable, Hashable, Sendable {
    /// Five stages only. After a rejection, change the conference and go back to `.writing`.
    public enum Stage: String, Codable, CaseIterable, Sendable, Comparable {
        case idea, experiments, writing, submitted, decided

        public var isSubmitted: Bool { self >= .submitted }

        public static func < (a: Stage, b: Stage) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    /// The edition of a ccfddl conference series it is submitted to, such as (`AI/cvpr`, 2027).
    /// The paper reads it, as a `StoredTarget`.
    public struct Target: Encodable, Hashable, Sendable {
        public var series: String
        public var year: Int
        /// One round of a multi-round edition; `nil` follows the next upcoming round.
        public var round: String?

        public init(series: String, year: Int, round: String? = nil) {
            self.series = series
            self.year = year
            self.round = round
        }

        public func encode(to encoder: any Encoder) throws {
            try StoredTarget.conference(series: series, year: year, round: round).encode(to: encoder)
        }
    }

    /// A target as files keep it, the form earlier builds can read: a conference edition, or, in
    /// those builds, one of the paper's own deadlines.
    enum StoredTarget: Codable {
        case conference(series: String, year: Int, round: String?)
        case custom(id: UUID)
    }

    public var id: UUID
    public var title: String
    /// The conference it is submitted to; `nil` for work that is due by deadlines of its own.
    public var target: Target?
    /// Deadlines of its own, such as the supplementary material, the camera-ready version or the
    /// letters for an application.
    public var deadlines: [CustomDeadline]
    /// The deadline of its own it aims at while it has no conference, whose paper submission is
    /// the main deadline otherwise: the plan counts back from it and is measured against it.
    public var mainDeadline: UUID?
    /// The conference's deadlines ticked off, by `DeadlineItem.id`, such as a registered abstract.
    public var doneDeadlines: [String]
    public var stage: Stage
    public var blocks: [TimeBlock]
    public var milestones: [Milestone]
    public var todos: [TodoItem]
    public var notes: String
    public var overleafURL: String
    public var githubURL: String
    /// One email thread per recipient group that has had an update.
    public var threads: [MailThread]
    /// Who may hear about it in the updates of the other papers, as `Person.id`s from the
    /// recipient groups. Empty, as everything starts, keeps it to the user.
    public var visibleTo: [UUID]
    /// How tall each track of its bar is in the overview, the whole bar where no blocks share days,
    /// once the user has dragged its row's edge; `nil` fits the bar to its blocks.
    public var trackHeight: Double?
    /// The group of other work it belongs to (`ItemGroup`); `nil` for a paper.
    public var groupID: UUID?
    /// When it was put away in the Archive; `nil` while it is in its group.
    public var archivedAt: Date?
    public var createdAt: Date

    /// A paper, rather than an item of another group, which has no stages or progress emails.
    public var isPaper: Bool {
        groupID == nil
    }

    /// When the work on it started: the first day of its plan, or else when it was added.
    public var startedAt: Date {
        blocks.map(\.start).min()?.startDate() ?? createdAt
    }

    /// Decided, for a paper; marked done, for an item, whose only stages are these two.
    public var isFinished: Bool {
        stage == .decided
    }

    /// Still under way, as the menu bar window lists it: not decided or done, or with a deadline
    /// of `deadlines`, its own, still ahead, such as a camera-ready.
    public func isUnderWay(_ deadlines: PaperDeadlines, now: Date) -> Bool {
        !isFinished || deadlines.next(after: now) != nil
    }

    public init(
        id: UUID = UUID(), title: String, target: Target? = nil, deadlines: [CustomDeadline] = [],
        mainDeadline: UUID? = nil, doneDeadlines: [String] = [], stage: Stage = .idea,
        blocks: [TimeBlock] = [], milestones: [Milestone] = [], todos: [TodoItem] = [], notes: String = "",
        overleafURL: String = "", githubURL: String = "",
        threads: [MailThread] = [], visibleTo: [UUID] = [], trackHeight: Double? = nil, groupID: UUID? = nil,
        archivedAt: Date? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.target = target
        self.deadlines = deadlines
        self.mainDeadline = mainDeadline
        self.doneDeadlines = doneDeadlines
        self.stage = stage
        self.blocks = blocks
        self.milestones = milestones
        self.todos = todos
        self.notes = notes
        self.overleafURL = overleafURL
        self.githubURL = githubURL
        self.threads = threads
        self.visibleTo = visibleTo
        self.trackHeight = trackHeight
        self.groupID = groupID
        self.archivedAt = archivedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, target, deadlines, mainDeadline, doneDeadlines, stage, blocks, milestones, todos, notes,
            overleafURL, githubURL, threads, visibleTo, trackHeight, groupID, archivedAt, createdAt
    }

    /// The single supervisor thread of the first builds, read, never written.
    private enum LegacyKeys: String, CodingKey {
        case supervisorThread
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        title = c(.title, default: "")
        deadlines = c.list(.deadlines, once: \.id)
        mainDeadline = c(.mainDeadline, default: nil)
        doneDeadlines = c(.doneDeadlines, default: [])
        switch c(.target, default: StoredTarget?.none) {
        case let .conference(series, year, round):
            target = Target(series: series, year: year, round: round)
        case let .custom(id):
            // The deadline of its own it aimed at, which `UserData` moves into it.
            target = nil
            mainDeadline = mainDeadline ?? id
        case nil:
            target = nil
        }
        stage = c(.stage, default: .idea)
        blocks = c.list(.blocks, once: \.id)
        milestones = c.list(.milestones, once: \.id)
        todos = c.list(.todos, once: \.id)
        notes = c(.notes, default: "")
        overleafURL = c(.overleafURL, default: "")
        githubURL = c(.githubURL, default: "")
        threads = c.list(.threads)
        let legacy = try LenientContainer(decoder, keyedBy: LegacyKeys.self)
        if let thread: MailThread = legacy(.supervisorThread, default: nil) {
            threads.append(thread)
        }
        visibleTo = c(.visibleTo, default: [])
        trackHeight = c(.trackHeight, default: nil)
        groupID = c(.groupID, default: nil)
        archivedAt = c(.archivedAt, default: nil)
        createdAt = c(.createdAt, default: Date())
    }

    /// The thread with `groupID`, if an update went to that group.
    public func thread(for groupID: UUID) -> MailThread? {
        threads.first { $0.groupID == groupID }
    }

    /// When the last update went out, to any group.
    public var lastSentAt: Date? {
        threads.compactMap(\.lastSentAt).max()
    }

    /// Keeps `thread` as the thread with its group, in place of the one before.
    public mutating func keep(_ thread: MailThread) {
        if let index = threads.firstIndex(where: { $0.groupID == thread.groupID }) {
            threads[index] = thread
        } else {
            threads.append(thread)
        }
    }

    /// Forgets the thread with a group, so that the next update to it starts a new one.
    public mutating func forgetThread(with groupID: UUID) {
        threads.removeAll { $0.groupID == groupID }
    }

    /// Gives threads that belong to no group yet, from the first builds, to `groupID`.
    func adoptingUnassignedThreads(into groupID: UUID) -> Paper {
        var paper = self
        for index in paper.threads.indices where paper.threads[index].groupID == MailThread.unassigned {
            paper.threads[index].groupID = groupID
        }
        return paper
    }
}

/// The email thread about one paper with one recipient group.
public struct MailThread: Codable, Hashable, Sendable {
    public var groupID: UUID
    public var subject: String
    /// The Message-ID of the first email, as Mail reports it. `nil` when the thread was started
    /// as a draft in another mail app, or when Mail had not yet reported it.
    public var messageID: String?
    public var startedAt: Date
    public var lastSentAt: Date?
    /// Whether its updates tell of the other work its group may hear about, as the last one did.
    public var includesOtherWork: Bool

    public init(
        groupID: UUID, subject: String, messageID: String? = nil, startedAt: Date, lastSentAt: Date? = nil,
        includesOtherWork: Bool = false
    ) {
        self.groupID = groupID
        self.subject = subject
        self.messageID = messageID
        self.startedAt = startedAt
        self.lastSentAt = lastSentAt
        self.includesOtherWork = includesOtherWork
    }

    /// The group of a thread from before groups existed, until its paper is read in full.
    static let unassigned = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    enum CodingKeys: String, CodingKey {
        case groupID, subject, messageID, startedAt, lastSentAt, includesOtherWork
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        groupID = c(.groupID, default: Self.unassigned)
        subject = try c.required(.subject)
        messageID = c(.messageID, default: nil)
        startedAt = c(.startedAt, default: Date())
        lastSentAt = c(.lastSentAt, default: nil)
        includesOtherWork = c(.includesOtherWork, default: false)
    }
}
