import DrBarKit
import Foundation

/// A conference series in ccfddl's `allconf.yml`:
///
///     - title: CVPR
///       description: IEEE/CVF Conference on Computer Vision and Pattern Recognition
///       sub: AI
///       rank: { ccf: A, core: A*, thcpl: A }
///       dblp: cvpr
///       conference_key: AI/cvpr
///       confs:
///         - year: 2027
///           id: cvpr27
///           link: https://cvpr.thecvf.com/Conferences/2027
///           timeline:
///             - abstract_deadline: '2026-11-10 23:59:59'
///               deadline: '2026-11-16 23:59:59'
///           timezone: UTC-12
///           date: June 20-25, 2027
///           place: Seattle, WA, United States
///
/// Editions and rounds are decoded leniently: one malformed entry is skipped, not the whole file.
struct CCFSeries: Decodable {
    let title: String
    let description: String?
    let sub: String
    let rank: Rank?
    let dblp: String?
    let conferenceKey: String?
    let editions: [Edition]

    /// The ranks of the three lists, each read on its own, so that one odd value costs only itself.
    struct Rank: Decodable {
        let ccf: String?
        let core: String?
        let thcpl: String?

        enum CodingKeys: String, CodingKey {
            case ccf, core, thcpl
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ccf = try? c.decodeIfPresent(String.self, forKey: .ccf)
            core = try? c.decodeIfPresent(String.self, forKey: .core)
            thcpl = try? c.decodeIfPresent(String.self, forKey: .thcpl)
        }
    }

    struct Edition: Decodable {
        let year: Int
        let id: String
        let link: String?
        let timeline: [Round]
        let timezone: String?
        let date: String?
        let place: String?

        /// The time zone as written, or AoE, as ccfddl means when none is given.
        var timeZoneText: String {
            timezone?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "AoE"
        }

        enum CodingKeys: String, CodingKey {
            case year, id, link, timeline, timezone, date, place
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            year = try c.decodeYear(forKey: .year)
            id = try c.decode(String.self, forKey: .id)
            link = try c.decodeIfPresent(String.self, forKey: .link)
            timeline = try c.decodeIfPresent([Lenient<Round>].self, forKey: .timeline)?.compactMap(\.value) ?? []
            timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
            date = try c.decodeIfPresent(String.self, forKey: .date)
            place = try c.decodeIfPresent(String.self, forKey: .place)
        }
    }

    struct Round: Decodable {
        let abstractDeadline: String?
        let deadline: String?
        let rebuttalDeadline: String?
        let decisionDeadline: String?
        let comment: String?

        enum CodingKeys: String, CodingKey {
            case abstractDeadline = "abstract_deadline"
            case deadline
            case rebuttalDeadline = "rebuttal_deadline"
            case decisionDeadline = "decision_deadline"
            case comment
        }
    }

    enum CodingKeys: String, CodingKey {
        case title, description, sub, rank, dblp, confs
        case conferenceKey = "conference_key"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        sub = try c.decode(String.self, forKey: .sub)
        rank = try? c.decodeIfPresent(Rank.self, forKey: .rank)
        dblp = try? c.decodeIfPresent(String.self, forKey: .dblp)
        conferenceKey = try c.decodeIfPresent(String.self, forKey: .conferenceKey)
        editions = try c.decodeIfPresent([Lenient<Edition>].self, forKey: .confs)?.compactMap(\.value) ?? []
    }
}

/// A conference's acceptance rates in ccfddl's `allacc.yml`:
///
///     - title: AAAI
///       accept_rates:
///       - year: 2025
///         submitted: 12957
///         accepted: 3032
///         str: 23.4%(3032/12957 25')
///         rate: 0.23400478505826966
///         source: https://csconfstats.xoveexu.com/
///       conference_key: AI/aaai
///
/// A year without a rate, or without the counts to work it out, is skipped, not the conference.
struct CCFAcceptance: Decodable {
    let title: String
    let conferenceKey: String?
    let years: [Year]

    struct Year: Decodable {
        let year: Int
        let rate: Double
        let submitted: Int?
        let accepted: Int?

        enum CodingKeys: String, CodingKey {
            case year, rate, submitted, accepted
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            year = try c.decodeYear(forKey: .year)
            submitted = try? c.decodeIfPresent(Int.self, forKey: .submitted)
            accepted = try? c.decodeIfPresent(Int.self, forKey: .accepted)
            if let rate = try? c.decode(Double.self, forKey: .rate) {
                self.rate = rate
            } else if let submitted, let accepted, submitted > 0 {
                rate = Double(accepted) / Double(submitted)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .rate, in: c, debugDescription: "No rate")
            }
            guard (0...1).contains(rate) else {
                throw DecodingError.dataCorruptedError(forKey: .rate, in: c, debugDescription: "Not a rate")
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case title
        case conferenceKey = "conference_key"
        case years = "accept_rates"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        conferenceKey = try c.decodeIfPresent(String.self, forKey: .conferenceKey)
        years = try c.decodeIfPresent([Lenient<Year>].self, forKey: .years)?.compactMap(\.value) ?? []
    }
}

extension KeyedDecodingContainer {
    /// A year is an integer, but a quoted "2027" should not cost what it is the year of.
    func decodeYear(forKey key: Key) throws -> Int {
        if let year = try? decode(Int.self, forKey: key) {
            return year
        }
        guard let year = Int(try decode(String.self, forKey: key)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a year")
        }
        return year
    }
}
