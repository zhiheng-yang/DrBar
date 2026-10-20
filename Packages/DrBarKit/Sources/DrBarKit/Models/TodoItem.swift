import Foundation

/// A small task of a paper, such as "Rerun PPO with five seeds".
public struct TodoItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isDone
    }

    public init(from decoder: any Decoder) throws {
        let c = try LenientContainer(decoder, keyedBy: CodingKeys.self)
        id = c(.id, default: UUID())
        title = c(.title, default: "")
        isDone = c(.isDone, default: false)
    }
}
