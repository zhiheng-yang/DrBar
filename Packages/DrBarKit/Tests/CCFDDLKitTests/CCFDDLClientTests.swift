import DrBarKit
import Foundation
import Testing

@testable import CCFDDLKit

/// Answers requests with whatever the current test sets.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond:
        (@Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let answer = Self.respond!(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct CCFDDLClientTests {
    let files: AppFiles
    let client: CCFDDLClient

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "drbar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        files = AppFiles(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        client = CCFDDLClient(files: files, userAgent: "DrBar/test", session: URLSession(configuration: configuration))
        StubProtocol.requests = []
    }

    @Test func downloadReplacesTheCacheAndRemembersTheETag() async throws {
        let yaml = Data(try sampleYAML().utf8)
        StubProtocol.respond = { _ in
            (200, ["ETag": "W/\"abc\"", "Last-Modified": "Mon, 12 Oct 2026 10:15:06 GMT"], yaml)
        }

        guard case let .updated(catalog) = try await client.sync(now: referenceNow) else {
            Issue.record("Expected new data")
            return
        }
        #expect(catalog.series.count == 7)
        #expect(FileManager.default.fileExists(atPath: files.rawData.path))
        #expect(JSONFile.read(ConferenceCatalog.self, from: files.catalog) == catalog)
        let state = await client.state()
        #expect(state.etag == "W/\"abc\"")
        #expect(state.seriesCount == 6)
        #expect(state.lastSuccess == referenceNow)
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "User-Agent") == "DrBar/test")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func secondRequestIsConditionalAnd304KeepsTheCache() async throws {
        let yaml = Data(try sampleYAML().utf8)
        StubProtocol.respond = { _ in
            (200, ["ETag": "W/\"abc\"", "Last-Modified": "Mon, 12 Oct 2026 10:15:06 GMT"], yaml)
        }
        _ = try await client.sync(now: referenceNow)

        StubProtocol.respond = { _ in (304, [:], Data()) }
        let later = referenceNow.addingTimeInterval(12 * 3600)
        guard case .notModified = try await client.sync(now: later) else {
            Issue.record("Expected not modified")
            return
        }
        let request = try #require(StubProtocol.requests.last { $0.url == CCFDDLClient.dataURL })
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 12 Oct 2026 10:15:06 GMT")
        #expect(await client.state().lastSuccess == later)
        #expect(await client.cachedCatalog(now: later)?.series.count == 7)
    }

    @Test func downloadWithFarFewerConferencesIsRejected() async throws {
        let yaml = Data(try sampleYAML().utf8)
        StubProtocol.respond = { _ in (200, [:], yaml) }
        _ = try await client.sync(now: referenceNow)
        let cached = try Data(contentsOf: files.rawData)

        let tiny = Data(
            """
            - title: Lonely
              description: The only conference left
              sub: AI
              rank: { ccf: A }
              conference_key: AI/lonely
              confs:
              - year: 2027
                id: lonely27
                timeline:
                - deadline: '2026-12-01 23:59:59'
                timezone: AoE
            """.utf8)
        StubProtocol.respond = { _ in (200, [:], tiny) }
        await #expect(throws: CCFDDLClient.SyncError.self) {
            try await client.sync(now: referenceNow)
        }
        #expect(try Data(contentsOf: files.rawData) == cached)
    }

    @Test func downloadWhoseEditionsCannotBeReadIsRejected() async throws {
        let yaml = try sampleYAML()
        StubProtocol.respond = { _ in (200, [:], Data(yaml.utf8)) }
        _ = try await client.sync(now: referenceNow)
        let cached = try Data(contentsOf: files.rawData)

        // As if ccfddl renamed a field: every conference is there, with nothing in it; or wrote every
        // time zone in a way this version cannot read.
        for unreadable in [
            yaml.replacingOccurrences(of: "confs:", with: "editions:"),
            yaml.replacing(/timezone: .*/, with: "timezone: Etc/GMT+12"),
        ] {
            StubProtocol.respond = { _ in (200, [:], Data(unreadable.utf8)) }
            await #expect(throws: CCFDDLClient.SyncError.self) {
                try await client.sync(now: referenceNow)
            }
        }
        #expect(try Data(contentsOf: files.rawData) == cached)
        #expect(await client.cachedCatalog(now: referenceNow)?.series.count == 7)
    }

    @Test func errorPageIsRejectedAndNothingIsWritten() async throws {
        StubProtocol.respond = { _ in (503, [:], Data("Service unavailable".utf8)) }
        await #expect(throws: CCFDDLClient.SyncError.self) {
            try await client.sync(now: referenceNow)
        }
        StubProtocol.respond = { _ in (200, [:], Data("<html>oops</html>".utf8)) }
        await #expect(throws: (any Error).self) {
            try await client.sync(now: referenceNow)
        }
        #expect(!FileManager.default.fileExists(atPath: files.rawData.path))
        #expect(await client.state().lastAttempt == referenceNow)
        #expect(await client.state().lastSuccess == nil)
    }

    @Test func acceptanceRatesComeWithTheConferencesAndOnTheirOwn() async throws {
        let yaml = Data(try sampleYAML().utf8)
        let rates = Data(AcceptanceTests.yaml.utf8)
        StubProtocol.respond = { request in
            request.url == CCFDDLClient.acceptanceURL
                ? (200, ["ETag": "\"acc\""], rates) : (200, ["ETag": "\"conf\""], yaml)
        }
        guard case let .updated(catalog) = try await client.sync(now: referenceNow) else {
            Issue.record("Expected new data")
            return
        }
        #expect(catalog.series(withKey: "AI/cvpr")?.latestAcceptance?.year == 2026)
        #expect(FileManager.default.fileExists(atPath: files.rawAcceptance.path))
        #expect(await client.state().acceptanceETag == "\"acc\"")

        // The conferences unchanged and the rates new: the catalog has the new ones.
        let newer = Data(AcceptanceTests.yaml.replacingOccurrences(of: "0.2541", with: "0.26").utf8)
        StubProtocol.respond = { request in
            request.url == CCFDDLClient.acceptanceURL ? (200, [:], newer) : (304, [:], Data())
        }
        guard case let .updated(again) = try await client.sync(now: referenceNow) else {
            Issue.record("Expected new rates")
            return
        }
        #expect(again.series(withKey: "AI/cvpr")?.latestAcceptance?.rate == 0.26)
        let conditional = StubProtocol.requests.filter { $0.url == CCFDDLClient.acceptanceURL }.last
        #expect(conditional?.value(forHTTPHeaderField: "If-None-Match") == "\"acc\"")

        // Neither changed.
        StubProtocol.respond = { _ in (304, [:], Data()) }
        guard case .notModified = try await client.sync(now: referenceNow) else {
            Issue.record("Expected not modified")
            return
        }
        // New conferences, but no rates to be had: the ones from before stay.
        StubProtocol.respond = { request in
            request.url == CCFDDLClient.acceptanceURL ? (500, [:], Data()) : (200, [:], yaml)
        }
        guard case let .updated(kept) = try await client.sync(now: referenceNow) else {
            Issue.record("Expected new data")
            return
        }
        #expect(kept.series(withKey: "AI/cvpr")?.latestAcceptance?.rate == 0.26)
    }

    @Test func bundledRatesServeUntilADownloadBringsSome() async throws {
        let snapshot = try #require(
            Bundle.module.url(forResource: "sample", withExtension: "yml", subdirectory: "Fixtures"))
        let bundled = FileManager.default.temporaryDirectory.appending(path: "allacc-\(UUID().uuidString).yml")
        try Data(AcceptanceTests.yaml.utf8).write(to: bundled)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = CCFDDLClient(
            files: files, userAgent: "DrBar/test", bundledAcceptance: bundled,
            session: URLSession(configuration: configuration))
        let catalog = try await client.installSnapshot(at: snapshot, now: referenceNow)
        #expect(catalog.series(withKey: "AI/cvpr")?.acceptance.count == 2)
        #expect(!FileManager.default.fileExists(atPath: files.rawAcceptance.path))
    }

    @Test func bundledSnapshotIsUsedWithoutTouchingTheDownloadCache() async throws {
        let snapshot = try #require(
            Bundle.module.url(forResource: "sample", withExtension: "yml", subdirectory: "Fixtures"))
        let catalog = try await client.installSnapshot(at: snapshot, now: referenceNow)
        #expect(catalog.series.count == 7)
        #expect(!FileManager.default.fileExists(atPath: files.rawData.path))
        #expect(await client.state().snapshotDate == utc("2026-10-12 00:00:00"))
        #expect(await client.cachedCatalog(now: referenceNow) == catalog)
    }
}

/// Checks the snapshot bundled with the app, when it is present (`scripts/update-snapshot.sh`).
@Suite struct BundledSnapshotTests {
    static let snapshotURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CCFDDLKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // DrBarKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appending(path: "App/Resources/allconf.yml")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: snapshotURL.path)))
    func bundledSnapshotParses() throws {
        let data = try Data(contentsOf: Self.snapshotURL)
        let parsed = try DeadlineParser.parse(yaml: data, now: Date())
        #expect(parsed.seriesCount > 200)
        #expect(parsed.catalog.series.contains { $0.id == "AI/cvpr" })
        #expect(CCFDDLClient.snapshotDate(in: data) != nil)
        // Every time zone in the snapshot is one the app understands.
        let unknown = Set(
            parsed.catalog.series.flatMap(\.editions).map(\.timeZone).filter { DeadlineTimeZone.ccf($0) == nil })
        #expect(unknown.isEmpty, "Unrecognized time zones: \(unknown.sorted())")
        // Every rank is one of its list's levels, as the filters offer them.
        let series = parsed.catalog.series
        #expect(series.allSatisfy { ["A", "B", "C", "N", nil].contains($0.ccfRank) })
        #expect(series.allSatisfy { ["A*", "A", "B", "C", "N", nil].contains($0.coreRank) })
        #expect(series.allSatisfy { ["A", "B", "N", nil].contains($0.thcplRank) })
        #expect(series.first { $0.id == "AI/cvpr" }?.coreRank == "A*")
    }

    static let acceptanceURL = snapshotURL.deletingLastPathComponent().appending(path: "allacc.yml")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: acceptanceURL.path)))
    func bundledAcceptanceRatesParseAndFitTheConferences() throws {
        let rates = try DeadlineParser.parseAcceptance(yaml: Data(contentsOf: Self.acceptanceURL))
        #expect(rates.count > 100)
        let snapshot = try Data(contentsOf: Self.snapshotURL)
        let catalog = try DeadlineParser.parse(yaml: snapshot, now: Date()).catalog.withAcceptance(rates)
        // Nearly every conference with rates is one of the snapshot's.
        let matched = catalog.series.filter { !$0.acceptance.isEmpty }.count
        #expect(matched * 10 >= rates.count * 9, "Only \(matched) of \(rates.count) matched")
        #expect(catalog.series.first { $0.id == "AI/cvpr" }?.latestAcceptance != nil)
    }
}
