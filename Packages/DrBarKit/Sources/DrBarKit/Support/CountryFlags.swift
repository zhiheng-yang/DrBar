import Foundation

/// The flags of the countries a conference meets in, read from where ccfddl says it meets: 🇲🇦 for
/// "Marrakesh, Morocco". The places are written freely, so the country is looked for from the end,
/// past "(Hybrid)" and "/ Online"; a place whose country is not clear gets no flag rather than a
/// wrong one.
public enum CountryFlags {
    /// The flags of the countries `place` names, in the order of its venues, each once; empty for
    /// "Virtual" or "TBD".
    public static func flags(in place: String) -> String {
        var codes: [String] = []
        for venue in venues(in: place) {
            for code in countries(in: venue) where !codes.contains(code) {
                codes.append(code)
            }
        }
        return codes.map(flag).joined()
    }

    /// The venues of a place: those apart by ";", and those joined by "and" where each has its own
    /// country after a comma, as in "Atlanta, USA and Cambridge, UK".
    static func venues(in place: String) -> [String] {
        place.replacingOccurrences(of: "，", with: ",").split(separator: ";").flatMap { venue -> [String] in
            let pieces = venue.split(separator: /\s+(?:and|&)\s+/).map(String.init)
            return pieces.count > 1 && pieces.allSatisfy { $0.contains(",") } ? pieces : [String(venue)]
        }
    }

    /// The countries of one venue, from its last part that names any, unless that is only what
    /// stands for a state or a region of a country, such as "CA", and an earlier part names
    /// something more certain, such as "Vancouver". None for a place in Taiwan, whatever else it
    /// names. Only the last part with any words, where the country goes, is searched word by word.
    static func countries(in venue: String) -> [String] {
        let parts = venue.replacing(/\([^)]*\)/, with: "").split(separator: ",").map { normalized(String($0)) }
            .filter { !$0.isEmpty }.reversed().enumerated()
            .map { index, part in match(part, byWord: index == 0) }
        guard !parts.contains(where: { $0.codes.contains("") }) else { return [] }
        let found = parts.filter { !$0.codes.isEmpty }
        return (found.first { !$0.isWeak } ?? found.first)?.codes ?? []
    }

    private struct Match {
        var codes: [String] = []
        /// Found by a name that something earlier in the place may make more particular.
        var isWeak = false
    }

    private static func match(_ text: String, byWord: Bool) -> Match {
        if let code = names[text] {
            return Match(codes: [code], isWeak: weak.contains(text))
        }
        let pieces = text.split(separator: /\s+(?:and|&)\s+|\s*\/\s*/).map(String.init)
        if pieces.count > 1 {
            let matches = pieces.map { match($0, byWord: byWord) }.filter { !$0.codes.isEmpty }
            return Match(codes: matches.flatMap(\.codes), isWeak: matches.allSatisfy(\.isWeak))
        }
        // "Florida USA", "Vancouver BC Canada"; then "Singapore EXPO", "Hong Kong Disneyland".
        let words = text.split(separator: " ").map(String.init)
        guard byWord, !words.isEmpty else { return Match() }
        let counts = Array((1..<min(words.count, 4)).reversed())
        for key in counts.map({ words.suffix($0).joined(separator: " ") })
            + counts.map({ words.prefix($0).joined(separator: " ") })
        {
            if let code = names[key] {
                return Match(codes: [code], isWeak: weak.contains(key))
            }
        }
        return Match()
    }

    /// Lowercase, without accents, dots or punctuation around it: "U.S.A." becomes "usa".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:()")))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Every country by its English name, as the system has it, and by the other names places use.
    /// An empty code is a name that is not a country of its own here.
    private static let names: [String: String] = {
        let english = Locale(identifier: "en_US")
        var names: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy(\.isLetter), let name = english.localizedString(forRegionCode: code)
            else { continue }
            // "Hong Kong SAR China", "Myanmar (Burma)", "Bosnia & Herzegovina".
            let short = name.replacing(/\s+SAR China$|\s*\(.*\)$/, with: "")
            for variant in [name, short, short.replacingOccurrences(of: "&", with: "and")] {
                names[normalized(variant)] = code
            }
        }
        return names.merging(aliases) { $1 }
    }()

    /// Names that yield to something more certain earlier in the place: "Vancouver, CA" is in
    /// Canada, "Atlanta, Georgia" in the United States, "Hong Kong, China" has its own flag.
    private static let weak: Set<String> = [
        "ca", "be", "dc", "ny", "tx", "fl", "nj", "nv", "ut", "mi", "georgia", "china",
    ]

    private static let aliases: [String: String] = [
        "usa": "US", "us": "US", "united states of america": "US", "united state": "US", "america": "US",
        "uk": "GB", "great britain": "GB", "britain": "GB", "northern ireland": "GB",
        "england": "GB-ENG", "scotland": "GB-SCT", "wales": "GB-WLS", "new south wales": "AU",
        "korea": "KR", "republic of korea": "KR", "czech republic": "CZ", "turkey": "TR", "turkiye": "TR",
        "uae": "AE", "the netherlands": "NL", "holland": "NL", "china": "CN", "pr china": "CN", "prc": "CN",
        "hong kong sar": "HK", "macau": "MO", "macau sar": "MO", "macao sar": "MO", "russia": "RU",
        "viet nam": "VN", "st kitts": "KN", "be": "BE",
        // Taiwan's flag is left out of Apple's emoji in some regions, so its places go without one.
        "taiwan": "",
        // States, provinces and cities that places name without their country.
        "alabama": "US", "alaska": "US", "arizona": "US", "arkansas": "US", "california": "US", "ca": "US",
        "colorado": "US", "connecticut": "US", "delaware": "US", "florida": "US", "hawaii": "US", "idaho": "US",
        "illinois": "US", "indiana": "US", "iowa": "US", "kansas": "US", "kentucky": "US", "louisiana": "US",
        "maine": "US", "maryland": "US", "massachusetts": "US", "michigan": "US", "minnesota": "US",
        "mississippi": "US", "missouri": "US", "montana": "US", "nebraska": "US", "nevada": "US",
        "new hampshire": "US", "new jersey": "US", "new mexico": "US", "new york": "US", "north carolina": "US",
        "north dakota": "US", "ohio": "US", "oklahoma": "US", "oregon": "US", "pennsylvania": "US",
        "rhode island": "US", "south carolina": "US", "south dakota": "US", "tennessee": "US", "texas": "US",
        "utah": "US", "vermont": "US", "virginia": "US", "washington": "US", "west virginia": "US",
        "wisconsin": "US", "wyoming": "US", "dc": "US", "washington dc": "US", "ny": "US", "tx": "US",
        "fl": "US", "nj": "US", "nv": "US", "ut": "US", "mi": "US", "atlanta": "US", "los angeles": "US",
        "san francisco": "US", "seattle": "US", "denver": "US", "philadelphia": "US", "new orleans": "US",
        "honolulu": "US", "bc": "CA", "british columbia": "CA", "ontario": "CA", "quebec": "CA", "alberta": "CA",
        "vancouver": "CA", "montreal": "CA", "toronto": "CA", "paris": "FR", "madrid": "ES", "barcelona": "ES",
        "santiago de compostela": "ES", "leuven": "BE", "mexico city": "MX", "abu dhabi": "AE", "dubai": "AE",
        "perth": "AU", "taipei": "",
    ]

    /// The regional indicators of a two-letter code; the tagged black flags of England, Scotland and
    /// Wales.
    private static func flag(_ code: String) -> String {
        let tags: String
        switch code {
        case "GB-ENG": tags = "gbeng"
        case "GB-SCT": tags = "gbsct"
        case "GB-WLS": tags = "gbwls"
        default:
            return String(
                String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
        }
        let scalars = tags.unicodeScalars.compactMap { Unicode.Scalar(0xE0000 + $0.value) }
        return "🏴" + String(String.UnicodeScalarView(scalars)) + "\u{E007F}"
    }
}
