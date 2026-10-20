import Foundation

/// Someone who gets progress emails.
public struct Person: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var email: String

    public init(id: UUID = UUID(), name: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.email = email
    }

    /// The email address without the spaces around it.
    public var address: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether an email can be addressed to them: something on both sides of one "@".
    public var hasAddress: Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts.contains(where: \.isEmpty) && !address.contains(" ")
    }

    /// The name, or the address of someone without one.
    public var displayName: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? address : name
    }

    /// "JD" for Jane Doe, as Contacts writes a monogram; one character for names in Chinese,
    /// Japanese or Korean, and the address's first letter for someone without a name.
    public var initials: String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        let name = name.trimmingCharacters(in: .whitespaces)
        let abbreviated = formatter.personNameComponents(from: name).map { formatter.string(from: $0) } ?? ""
        guard !abbreviated.isEmpty else { return address.prefix(1).uppercased() }
        let isLatin = abbreviated.unicodeScalars.allSatisfy { $0.properties.isAlphabetic && $0.value < 0x2E80 }
        return abbreviated.prefix(isLatin ? 2 : 1).uppercased()
    }

    /// "Jane Doe <jane.doe@example.org>", as an address field shows it.
    public var addressLine: String {
        displayName == address ? address : "\(displayName) <\(address)>"
    }

    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty && address.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, email
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        name = c(.name, default: "")
        email = c(.email, default: "")
    }
}

/// People who follow a paper's progress together, with one email thread per paper: the
/// supervisors, the collaborators, or a group of the user's own.
public struct RecipientGroup: Codable, Hashable, Identifiable, Sendable {
    /// What the group is for, which gives it a name until the user names it.
    public enum Kind: String, Codable, Sendable {
        case supervisors, collaborators, other
    }

    public var id: UUID
    public var kind: Kind
    /// Empty for the name of its kind.
    public var name: String
    public var people: [Person]
    /// The language of the summary and the image.
    public var language: MailLanguage
    /// Leave buffer blocks out of the image and the summary.
    public var hidesBufferBlocks: Bool

    public init(
        id: UUID = UUID(), kind: Kind, name: String = "", people: [Person] = [], language: MailLanguage = .english,
        hidesBufferBlocks: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.people = people
        self.language = language
        // Slack in a plan is the student's own business; collaborators may as well see it.
        self.hidesBufferBlocks = hidesBufferBlocks ?? (kind == .supervisors)
    }

    /// The people an email can be addressed to.
    public var recipients: [Person] {
        people.filter(\.hasAddress)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, people, language, hidesBufferBlocks
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        kind = c(.kind, default: .other)
        name = c(.name, default: "")
        people = c.list(.people)
        language = c(.language, default: .english)
        hidesBufferBlocks = c(.hidesBufferBlocks, default: kind == .supervisors)
    }
}

/// Who gets progress emails, and how they are signed and sent.
public struct MailSettings: Codable, Hashable, Sendable {
    public var groups: [RecipientGroup]
    /// The user's own name, used to sign the email.
    public var signature: String
    /// The user's address to send from, one of their accounts in Mail; empty for Mail's choice.
    public var senderAddress: String

    /// The groups everyone starts with. Their ids are fixed, so that the defaults are equal everywhere.
    public static let defaultGroups = [
        RecipientGroup(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, kind: .supervisors),
        RecipientGroup(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, kind: .collaborators),
    ]

    public init(groups: [RecipientGroup] = defaultGroups, signature: String = "", senderAddress: String = "") {
        self.groups = groups
        self.signature = signature
        self.senderAddress = senderAddress
    }

    /// Drops the rows that were added and never filled in.
    public mutating func removeBlankPeople() {
        for index in groups.indices {
            groups[index].people.removeAll(where: \.isBlank)
        }
    }

    enum CodingKeys: String, CodingKey {
        case groups, signature, senderAddress
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        groups = c.list(.groups)
        signature = c(.signature, default: "")
        senderAddress = c(.senderAddress, default: "")
    }
}

extension UserData {
    /// Everyone in the recipient groups, by id.
    public var people: [UUID: Person] {
        Dictionary(mail.groups.flatMap(\.people).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Removes a recipient group, and with it the threads with that group, and its people from the
    /// blocks they worked on and from what they could hear about, wherever the work is.
    public mutating func removeRecipientGroup(_ id: UUID) {
        mail.groups.removeAll { $0.id == id }
        updateEveryPaper { $0.forgetThread(with: id) }
        forgetRemovedPeople()
    }

    /// Whether any paper, also one in the Archive or Recently Deleted, has a thread with a group.
    public func hasThreads(with groupID: UUID) -> Bool {
        everyPaper.contains { $0.thread(for: groupID) != nil }
    }

    /// Takes people who are no longer in any group off the blocks, and off what they could hear
    /// about, wherever the work is.
    public mutating func forgetRemovedPeople() {
        let known = Set(people.keys)
        updateEveryPaper { paper in
            for b in paper.blocks.indices where paper.blocks[b].people.contains(where: { !known.contains($0) }) {
                paper.blocks[b].people.removeAll { !known.contains($0) }
            }
            if paper.visibleTo.contains(where: { !known.contains($0) }) {
                paper.visibleTo.removeAll { !known.contains($0) }
            }
        }
    }

    /// The papers and items under way, besides the one with `paperID`, that every one of
    /// `recipients` may hear about, in the order of the sidebar, with their deadlines. None without
    /// recipients, and none without a title, which would tell them nothing.
    public func work(
        visibleTo recipients: [Person], besides paperID: UUID, catalog: ConferenceCatalog, now: Date,
        calendar: Calendar = .gregorianLocal
    ) -> [(paper: Paper, deadlines: PaperDeadlines)] {
        let ids = Set(recipients.map(\.id))
        guard !ids.isEmpty else { return [] }
        return groupOrder.flatMap { items(in: $0) }.compactMap { paper in
            guard paper.id != paperID, ids.isSubset(of: paper.visibleTo),
                !paper.title.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            let deadlines = PaperDeadlines.resolve(paper, catalog: catalog, now: now, calendar: calendar)
            return paper.isUnderWay(deadlines, now: now) ? (paper, deadlines) : nil
        }
    }
}

/// The single supervisor of the first builds, read once and turned into the supervisors group.
struct LegacySupervisor: Decodable {
    var name: String
    var email: String
    var signature: String
    var senderAddress: String
    var language: MailLanguage
    var hidesBufferBlocks: Bool

    enum CodingKeys: String, CodingKey {
        case name, email, signature, senderAddress, language, hidesBufferBlocks
    }

    init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        name = c(.name, default: "")
        email = c(.email, default: "")
        signature = c(.signature, default: "")
        senderAddress = c(.senderAddress, default: "")
        language = c(.language, default: .english)
        hidesBufferBlocks = c(.hidesBufferBlocks, default: true)
    }

    var mailSettings: MailSettings {
        var groups = MailSettings.defaultGroups
        let supervisor = Person(name: name, email: email)
        groups[0].people = supervisor.isBlank ? [] : [supervisor]
        groups[0].hidesBufferBlocks = hidesBufferBlocks
        for index in groups.indices {
            groups[index].language = language
        }
        return MailSettings(groups: groups, signature: signature, senderAddress: senderAddress)
    }
}
