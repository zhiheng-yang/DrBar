import Foundation

/// A followed date that ccfddl changed since the last sync.
public struct DeadlineChange: Hashable, Sendable {
    public var item: DeadlineItem
    public var oldText: String
    public var newText: String

    /// A compact "old → new" pair, such as `09-25` and `10-01`, or `TBD` and `10-01`.
    public var compact: (old: String, new: String) {
        ChangeDetector.compact(oldText, newText)
    }
}

/// Notices when ccfddl changes the raw text of a followed date.
public enum ChangeDetector {
    /// Compares `items` with what was seen before.
    ///
    /// Items seen for the first time are only recorded; items that are no longer followed are
    /// dropped, so `lastSeen` stays small.
    public static func detect(
        items: [DeadlineItem], lastSeen: [String: String]
    )
        -> (changes: [DeadlineChange], lastSeen: [String: String])
    {
        var changes: [DeadlineChange] = []
        var seen: [String: String] = [:]
        for item in items {
            let text = item.value.raw.trimmingCharacters(in: .whitespaces)
            // Only a change that its alert can show: not seconds, nor how a time is written.
            if let old = lastSeen[item.id], old != text, compact(old, text).old != compact(old, text).new {
                changes.append(DeadlineChange(item: item, oldText: old, newText: text))
            }
            seen[item.id] = text
        }
        return (changes, seen)
    }

    /// What a pass that announces nothing keeps: what is followed for the first time as it is now,
    /// the rest as last seen, so that a change of it is still announced by the next pass that
    /// announces; what is no longer followed is dropped.
    public static func record(items: [DeadlineItem], lastSeen: [String: String]) -> [String: String] {
        var seen: [String: String] = [:]
        for item in items {
            seen[item.id] = lastSeen[item.id] ?? item.value.raw.trimmingCharacters(in: .whitespaces)
        }
        return seen
    }

    static func compact(_ old: String, _ new: String) -> (old: String, new: String) {
        func parts(_ text: String) -> (date: Substring, time: Substring)? {
            let pieces = text.split(separator: " ")
            guard let date = pieces.first, Day(string: String(date)) != nil else { return nil }
            let time = pieces.count > 1 ? pieces[1].prefix(5) : "23:59"
            return (date, time)
        }
        switch (parts(old), parts(new)) {
        case let (o?, n?):
            let sameYear = o.date.prefix(4) == n.date.prefix(4)
            func day(_ p: (date: Substring, time: Substring)) -> String {
                sameYear ? String(p.date.dropFirst(5)) : String(p.date)
            }
            if o.time != n.time {
                return ("\(day(o)) \(o.time)", "\(day(n)) \(n.time)")
            }
            return (day(o), day(n))
        case let (o?, nil):
            return (String(o.date.dropFirst(5)), new)
        case let (nil, n?):
            return (old, String(n.date.dropFirst(5)))
        case (nil, nil):
            return (old, new)
        }
    }
}
