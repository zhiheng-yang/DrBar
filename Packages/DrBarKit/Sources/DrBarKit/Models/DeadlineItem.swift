import Foundation

/// One dated entry of one round, such as "CVPR 2027, paper deadline".
///
/// The flat form of the catalog, used for noticing date changes.
public struct DeadlineItem: Hashable, Sendable, Identifiable {
    public var seriesKey: String
    public var editionID: String
    /// The series title, e.g. `CVPR`.
    public var title: String
    public var year: Int
    public var kind: DeadlineKind
    public var roundID: String
    public var roundLabel: String?
    public var value: DeadlineValue
    public var timeZone: String

    /// The same from one sync to the next while the round keeps its id; `CatalogRenames` follows one
    /// that does not.
    public var id: String {
        Self.id(edition: editionID, kind: kind, round: roundID)
    }

    /// The id of the date of `kind` in a round, by which reminders, ticks and date changes know it.
    public static func id(edition: String, kind: DeadlineKind, round: String) -> String {
        "\(edition)|\(kind.rawValue)|\(round)"
    }

    /// What an id made by `id(edition:kind:round:)` was made of.
    static func parts(of id: String) -> (edition: String, kind: DeadlineKind, round: String)? {
        let parts = id.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let kind = DeadlineKind(rawValue: parts[1]) else { return nil }
        return (parts[0], kind, parts[2])
    }

    /// "CVPR 2027", built from strings so the year never shows as "2,027".
    public var editionTitle: String {
        "\(title) \(String(year))"
    }

    /// "SIGMOD 2027 round 4", or "CVPR 2027" for an edition of one round.
    public var fullTitle: String {
        [editionTitle, roundLabel].compactMap { $0 }.joined(separator: " ")
    }
}

extension ConferenceRound {
    /// A short label that tells the rounds of one edition apart, or `nil` for a single round.
    ///
    /// ccfddl comments range from "Fall" to whole paragraphs; long ones are shown in the details
    /// and the tooltip, and the row shows the round number instead.
    public func label(roundCount: Int) -> String? {
        guard roundCount > 1 else { return nil }
        if let comment, comment == id, comment.count <= 16 {
            return comment
        }
        return "#\(index + 1)"
    }
}

extension ConferenceCatalog {
    /// All dated entries of the followed editions.
    public func items(following: Following) -> [DeadlineItem] {
        var items: [DeadlineItem] = []
        for s in series where following.followsAnyEdition(of: s.id) {
            for e in s.editions where following.follows(series: s.id, year: e.year) {
                for r in e.rounds {
                    for kind in DeadlineKind.allCases {
                        guard let value = r.value(kind) else { continue }
                        items.append(
                            DeadlineItem(
                                seriesKey: s.id, editionID: e.id, title: s.title, year: e.year,
                                kind: kind, roundID: r.id, roundLabel: r.label(roundCount: e.rounds.count),
                                value: value, timeZone: e.timeZone))
                    }
                }
            }
        }
        return items
    }
}
