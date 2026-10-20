import Foundation

/// Decodes an element of a list without failing the whole list when the element is malformed.
///
/// ccfddl is maintained by a community and occasionally has formatting slips, and a user file may
/// have been edited by hand: one bad entry should cost that entry, not the whole file.
public struct Lenient<Value: Decodable>: Decodable {
    public let value: Value?
    public let error: (any Error)?

    public init(from decoder: any Decoder) throws {
        do {
            value = try Value(from: decoder)
            error = nil
        } catch {
            value = nil
            self.error = error
        }
    }
}

/// Collects the problems met while decoding user data, so the caller can keep a copy of the
/// original file before anything is written back.
public final class DecodingReport: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    public init() {}

    public var issues: [String] {
        lock.withLock { storage }
    }

    func record(_ issue: String) {
        lock.withLock { storage.append(issue) }
    }
}

extension CodingUserInfoKey {
    /// Pass a `DecodingReport` under this key to learn which fields were replaced by defaults.
    public static let decodingReport = CodingUserInfoKey(rawValue: "DrBarDecodingReport")!
}

/// A keyed container that falls back to defaults instead of throwing.
///
/// Missing keys are normal: they appear whenever a newer version added a field. Keys that are
/// present but hold an unexpected value are reported through the `DecodingReport`.
struct LenientContainer<Key: CodingKey> {
    let container: KeyedDecodingContainer<Key>
    let report: DecodingReport?

    init(_ decoder: any Decoder, keyedBy: Key.Type) throws {
        container = try decoder.container(keyedBy: Key.self)
        report = decoder.userInfo[.decodingReport] as? DecodingReport
    }

    func callAsFunction<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        guard container.contains(key) else { return fallback() }
        do {
            return try container.decodeIfPresent(T.self, forKey: key) ?? fallback()
        } catch {
            report?.record(
                "\(container.codingPath.map(\.stringValue).joined(separator: ".")).\(key.stringValue): \(error)")
            return fallback()
        }
    }

    /// Decodes a list, skipping and reporting the elements that cannot be decoded.
    func list<T: Decodable>(_ key: Key) -> [T] {
        let items: [Lenient<T>] = self(key, default: [])
        for case let (index, item) in items.enumerated() where item.value == nil {
            report?.record("\(key.stringValue)[\(index)]: \(item.error.map { "\($0)" } ?? "unreadable")")
        }
        return items.compactMap(\.value)
    }

    func required<T: Decodable>(_ key: Key) throws -> T {
        try container.decode(T.self, forKey: key)
    }
}

/// Lets each id through once, for a file that may hold something twice, as one edited by hand
/// can: a repeat of what was let through is left out, and so is anything else with the same id,
/// which the report is told of.
struct OnceByID<Element: Equatable> {
    private let id: KeyPath<Element, UUID>
    private let report: DecodingReport?
    private var seen: [UUID: Element] = [:]

    init(_ id: KeyPath<Element, UUID>, report: DecodingReport?) {
        self.id = id
        self.report = report
    }

    /// `element`, or `nil` when one with its id was let through before.
    mutating func pass(_ element: Element) -> Element? {
        let key = element[keyPath: id]
        guard let earlier = seen[key] else {
            seen[key] = element
            return element
        }
        if earlier != element {
            report?.record("\(key): another entry has the same id")
        }
        return nil
    }

    mutating func pass(_ elements: [Element]) -> [Element] {
        elements.compactMap { pass($0) }
    }
}

extension LenientContainer {
    /// Decodes a list as `list` does, with each id once (`OnceByID`).
    func list<T: Decodable & Equatable>(_ key: Key, once id: KeyPath<T, UUID>) -> [T] {
        var once = OnceByID(id, report: report)
        return once.pass(list(key))
    }
}
