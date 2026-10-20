import DrBarKit
import Foundation

/// What the client remembers between syncs (`sync.json`).
public struct SyncState: Codable, Equatable, Sendable {
    public var etag: String?
    public var lastModified: String?
    /// The same for the acceptance rates.
    public var acceptanceETag: String?
    public var acceptanceLastModified: String?
    /// The last time ccfddl answered with data or with "not modified".
    public var lastSuccess: Date?
    public var lastAttempt: Date?
    /// Conferences in the last accepted file, to reject a download that lists far fewer.
    public var seriesCount: Int?
    /// When the data in use was published, for the bundled snapshot (from its header comment).
    public var snapshotDate: Date?

    public init() {}
}

/// Downloads, checks and caches ccfddl data: the conferences, and their acceptance rates beside
/// them.
///
/// Runs off the main actor: parsing `allconf.yml` takes a moment. The cache is replaced only by a
/// download that parses and lists at least half as many conferences as before. The acceptance
/// rates are a bonus: when they cannot be had, the conferences come without them, or with the
/// ones from before.
public actor CCFDDLClient {
    public static let dataURL = URL(string: "https://ccfddl.com/conference/allconf.yml")!
    public static let acceptanceURL = URL(string: "https://ccfddl.com/conference/allacc.yml")!

    public enum Outcome: Sendable {
        case notModified
        case updated(ConferenceCatalog)
    }

    public enum SyncError: Error, Sendable {
        case badStatus(Int)
        case tooFewConferences(found: Int, before: Int)
    }

    private let files: AppFiles
    private let session: URLSession
    private let url: URL
    private let acceptanceURL: URL
    /// The acceptance rates bundled with the app, used until a download has brought some.
    private let bundledAcceptance: URL?
    private let userAgent: String

    public init(
        files: AppFiles, userAgent: String, url: URL = CCFDDLClient.dataURL,
        acceptanceURL: URL = CCFDDLClient.acceptanceURL, bundledAcceptance: URL? = nil, session: URLSession? = nil
    ) {
        self.files = files
        self.userAgent = userAgent
        self.url = url
        self.acceptanceURL = acceptanceURL
        self.bundledAcceptance = bundledAcceptance
        self.session = session ?? URLSession(configuration: Self.configuration)
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        return configuration
    }

    public func state() -> SyncState {
        JSONFile.read(SyncState.self, from: files.syncState) ?? SyncState()
    }

    /// The catalog from `deadlines.json`. Rebuilt from the cached YAML when it was written by a
    /// version that parsed differently. `nil` when there is no usable cache.
    public func cachedCatalog(now: Date) -> ConferenceCatalog? {
        if let catalog = JSONFile.read(ConferenceCatalog.self, from: files.catalog),
            catalog.formatVersion == ConferenceCatalog.currentFormatVersion
        {
            return catalog
        }
        guard let data = try? Data(contentsOf: files.rawData),
            let parsed = try? DeadlineParser.parse(yaml: data, now: now)
        else { return nil }
        let catalog = parsed.catalog.withAcceptance(cachedAcceptance())
        try? JSONFile.write(catalog, to: files.catalog)
        return catalog
    }

    /// The acceptance rates last downloaded, or else those bundled with the app.
    private func cachedAcceptance() -> [AcceptanceRates] {
        for url in [files.rawAcceptance, bundledAcceptance].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let rates = try? DeadlineParser.parseAcceptance(yaml: data) {
                return rates
            }
        }
        return []
    }

    /// Uses the snapshot bundled with the app when there is no cache yet (first launch, offline).
    /// The snapshot is not copied into the cache, so the first download is never conditional.
    public func installSnapshot(at snapshot: URL, now: Date) throws -> ConferenceCatalog {
        let data = try Data(contentsOf: snapshot)
        let parsed = try DeadlineParser.parse(yaml: data, now: now)
        let catalog = parsed.catalog.withAcceptance(cachedAcceptance())
        try JSONFile.write(catalog, to: files.catalog)
        var state = state()
        state.seriesCount = state.seriesCount ?? parsed.seriesCount
        state.snapshotDate = Self.snapshotDate(in: data)
        try JSONFile.write(state, to: files.syncState)
        return catalog
    }

    /// Asks ccfddl for new data, sending the ETag and Last-Modified of the cached copy, then for
    /// the acceptance rates the same way.
    public func sync(now: Date) async throws -> Outcome {
        var state = state()
        state.lastAttempt = now
        // The attempt is remembered whatever happens; what was downloaded only once the catalog has
        // it, so that a catalog that could not be written is downloaded again.
        var kept = state
        defer { try? JSONFile.write(kept, to: files.syncState) }

        let (data, response) = try await session.data(
            for: request(url, etag: state.etag, lastModified: state.lastModified, cached: files.rawData))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        var parsed: DeadlineParser.Parsed?
        switch status {
        case 304:
            break
        case 200:
            let fresh = try DeadlineParser.parse(yaml: data, now: now)
            let before = state.seriesCount ?? 0
            guard fresh.seriesCount > 0, fresh.seriesCount * 2 >= before else {
                throw SyncError.tooFewConferences(found: fresh.seriesCount, before: before)
            }
            // Atomic; deadlines.json can always be rebuilt from allconf.yml.
            try data.write(to: files.rawData, options: .atomic)
            let http = response as? HTTPURLResponse
            state.etag = http?.value(forHTTPHeaderField: "ETag")
            state.lastModified = http?.value(forHTTPHeaderField: "Last-Modified")
            state.seriesCount = fresh.seriesCount
            parsed = fresh
        default:
            throw SyncError.badStatus(status)
        }
        state.lastSuccess = now

        let rates = await syncAcceptance(&state)
        guard parsed != nil || rates != nil, let base = parsed?.catalog ?? cachedCatalog(now: now) else {
            kept = state
            return .notModified
        }
        let catalog = base.withAcceptance(rates ?? cachedAcceptance())
        try JSONFile.write(catalog, to: files.catalog)
        kept = state
        return .updated(catalog)
    }

    /// The acceptance rates, when they changed and could be read; `nil` otherwise, whatever went
    /// wrong, so the ones from before stay.
    private func syncAcceptance(_ state: inout SyncState) async -> [AcceptanceRates]? {
        let request = request(
            acceptanceURL, etag: state.acceptanceETag, lastModified: state.acceptanceLastModified,
            cached: files.rawAcceptance)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let rates = try? DeadlineParser.parseAcceptance(yaml: data), !rates.isEmpty,
            (try? data.write(to: files.rawAcceptance, options: .atomic)) != nil
        else { return nil }
        state.acceptanceETag = http.value(forHTTPHeaderField: "ETag")
        state.acceptanceLastModified = http.value(forHTTPHeaderField: "Last-Modified")
        return rates
    }

    /// A request for `url`, conditional while the copy at `cached` is there.
    private func request(_ url: URL, etag: String?, lastModified: String?, cached: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if FileManager.default.fileExists(atPath: cached.path) {
            if let etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }
        return request
    }

    /// Reads the date from the snapshot's first line, `# ccfddl snapshot 2026-10-12`, written by
    /// `scripts/update-snapshot.sh`.
    static func snapshotDate(in data: Data) -> Date? {
        let firstLine = data.prefix(200).split(separator: UInt8(ascii: "\n"), maxSplits: 1).first
        guard let line = firstLine.flatMap({ String(data: Data($0), encoding: .utf8) }),
            line.hasPrefix("# ccfddl snapshot "),
            let day = Day(string: String(line.dropFirst("# ccfddl snapshot ".count).prefix(10)))
        else { return nil }
        return day.startDate(calendar: .gregorian(in: .gmt))
    }
}
