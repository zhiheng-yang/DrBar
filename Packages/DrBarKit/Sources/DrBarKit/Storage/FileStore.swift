import Foundation

/// The JSON format of every file the app writes. It must stay readable by later versions.
public enum DrBarJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder(report: DecodingReport? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let report {
            decoder.userInfo[.decodingReport] = report
        }
        return decoder
    }
}

/// Where the app keeps its files: `Application Support/DrBar/`. Inside the sandbox this is in
/// `~/Library/Containers/<bundle ID>/…`, so paths always come from `FileManager`.
public struct AppFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func applicationSupport() throws -> AppFiles {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appending(path: "DrBar", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppFiles(directory: directory)
    }

    /// The user's data. Written atomically, with `user.json.bak` kept before each overwrite.
    public var userData: URL { directory.appending(path: "user.json") }
    public var userDataBackup: URL { directory.appending(path: "user.json.bak") }
    /// The parsed deadline catalog, read at launch.
    public var catalog: URL { directory.appending(path: "deadlines.json") }
    /// The ccfddl data as downloaded.
    public var rawData: URL { directory.appending(path: "allconf.yml") }
    /// ccfddl's acceptance rates as downloaded.
    public var rawAcceptance: URL { directory.appending(path: "allacc.yml") }
    /// ETag, Last-Modified and sync times.
    public var syncState: URL { directory.appending(path: "sync.json") }
}

public enum FileStore {
    /// Copies `url` next to itself with a time stamp, e.g. `user.json.unreadable-20261012-210300`,
    /// unless an earlier copy there holds the same.
    @discardableResult
    public static func keepCopy(of url: URL, label: String, now: Date = Date()) throws -> URL {
        let contents = try Data(contentsOf: url)
        let prefix = "\(url.lastPathComponent).\(label)-"
        let earlier = try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        if let same = earlier?.first(where: {
            $0.lastPathComponent.hasPrefix(prefix) && (try? Data(contentsOf: $0)) == contents
        }) {
            return same
        }
        let copy = try place(for: url, label: label, now: now)
        try contents.write(to: copy)
        return copy
    }

    /// Moves `url` where `keepCopy` would copy it.
    static func moveAside(_ url: URL, label: String, now: Date = Date()) throws -> URL {
        let place = try place(for: url, label: label, now: now)
        try FileManager.default.moveItem(at: url, to: place)
        return place
    }

    /// Copies `url` over `destination`. The copy of a file locked in the Finder is not locked, so
    /// that it can be replaced in turn.
    static func copy(_ url: URL, over destination: URL) throws {
        try remove(destination)
        try FileManager.default.copyItem(at: url, to: destination)
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: destination.path)
    }

    private static func place(for url: URL, label: String, now: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        let place = url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent).\(label)-\(stamp)")
        try remove(place)
        return place
    }

    /// Removes what the app keeps at `url`, if anything, even if it was locked.
    private static func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
        try FileManager.default.removeItem(at: url)
    }
}

/// Reads and writes `user.json`. The file a save replaces becomes `user.json.bak` if it was read in
/// full; one that was not is set aside first, and one that cannot be is never written over.
public struct UserDataStore: Sendable {
    public enum LoadOutcome: Equatable, Sendable {
        /// No data yet: first launch.
        case fresh
        case loaded
        /// Some entries could not be read and were left out. `keptCopy` is where the file was set
        /// aside; without it the file is left as it is, and saving fails.
        case repaired(keptCopy: URL?)
        /// `user.json` could not be read, or was not there; the backup was used. Each that could not
        /// be read in full was set aside, `keptCopy` being where `user.json` went, or the backup.
        case restoredFromBackup(keptCopy: URL?, isPartial: Bool)
        /// Neither file could be read, and the app starts empty. `keptCopy` is where `user.json`, or
        /// the backup, was set aside.
        case unreadable(keptCopy: URL?)
    }

    public let file: URL
    public let backup: URL
    /// `user.json` as it was last read or written here, and whether it was read in full, so that a
    /// save need not read it again to know whether it may become the backup.
    private var known: (stamp: FileStamp, isWhole: Bool)?
    /// The files that could be neither read in full nor set aside.
    private var held: Set<URL> = []

    public init(files: AppFiles) {
        self.file = files.userData
        self.backup = files.userDataBackup
    }

    /// Reads `user.json`, or else its backup. What could not be read in full is set aside, and what
    /// could be read takes its place at once.
    public mutating func load(now: Date = Date()) -> (UserData, LoadOutcome) {
        known = nil
        held = []
        let (data, outcome) = read(now: now)
        if outcome != .fresh, outcome != .loaded {
            try? save(data)
        }
        return (data, outcome)
    }

    private mutating func read(now: Date) -> (UserData, LoadOutcome) {
        let fileManager = FileManager.default
        let hasFile = fileManager.fileExists(atPath: file.path)
        var kept: URL?
        if hasFile {
            let stamp = FileStamp(file)
            let read = try? Self.decode(Data(contentsOf: file))
            known = stamp.map { ($0, read?.issues.isEmpty == true) }
            if let read {
                guard read.issues.isEmpty else {
                    return (read.data, .repaired(keptCopy: setAside(file, wasRead: true, now: now)))
                }
                return (read.data, .loaded)
            }
            kept = setAside(file, wasRead: false, now: now)
        }
        guard fileManager.fileExists(atPath: backup.path) else {
            return (UserData(), hasFile ? .unreadable(keptCopy: kept) : .fresh)
        }
        guard let (restored, issues) = try? Self.decode(Data(contentsOf: backup)) else {
            let backupKept = setAside(backup, wasRead: false, now: now)
            return (UserData(), .unreadable(keptCopy: kept ?? backupKept))
        }
        let backupKept = issues.isEmpty ? nil : setAside(backup, wasRead: true, now: now)
        return (restored, .restoredFromBackup(keptCopy: kept ?? backupKept, isPartial: !issues.isEmpty))
    }

    /// Writes `data`. The file it replaces becomes the backup if it was read in full, and is set
    /// aside first if it was not.
    public mutating func save(_ data: UserData) throws {
        let stamp = FileStamp(file)
        if stamp != known?.stamp {
            // Changed by something else since it was last read or written here.
            let read = try? Self.decode(Data(contentsOf: file))
            known = stamp.map { ($0, read?.issues.isEmpty == true) }
            if known?.isWhole == false {
                setAside(file, wasRead: read != nil, now: Date())
            }
        }
        guard !held.contains(file) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSURLErrorKey: file])
        }
        if known?.isWhole == true, !held.contains(backup) {
            try FileStore.copy(file, over: backup)
        }
        try Self.encode(data).write(to: file, options: .atomic)
        known = FileStamp(file).map { ($0, true) }
    }

    /// Copies `url` next to itself. One that could not be read at all, so not copied either, is
    /// moved there instead; one read in part stays where it is, lest what was read be lost should
    /// writing in its place fail. One that can be neither copied nor moved is held.
    @discardableResult
    private mutating func setAside(_ url: URL, wasRead: Bool, now: Date) -> URL? {
        if let place = (try? FileStore.keepCopy(of: url, label: "unreadable", now: now))
            ?? (wasRead ? nil : try? FileStore.moveAside(url, label: "unreadable", now: now))
        {
            return place
        }
        held.insert(url)
        return nil
    }

    public static func encode(_ data: UserData) throws -> Data {
        try DrBarJSON.encoder().encode(data)
    }

    /// Decodes leniently and reports what had to be left out.
    public static func decode(_ json: Data) throws -> (data: UserData, issues: [String]) {
        let report = DecodingReport()
        let data = try DrBarJSON.decoder(report: report).decode(UserData.self, from: json)
        return (data, report.issues)
    }

    /// Decodes a file to import. Unlike `decode`, it refuses JSON without DrBar's format version,
    /// which any other file would otherwise pass for empty data.
    public static func decodeExported(_ json: Data) throws -> (data: UserData, issues: [String]) {
        struct Header: Decodable { var formatVersion: Int }
        _ = try JSONDecoder().decode(Header.self, from: json)
        return try decode(json)
    }
}

/// Tells a file from another written at the same path later.
struct FileStamp: Equatable {
    var number: Int
    var modified: Date

    init?(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let number = attributes[.systemFileNumber] as? Int, let modified = attributes[.modificationDate] as? Date
        else { return nil }
        self.number = number
        self.modified = modified
    }
}

/// Reads and writes small JSON files that can always be rebuilt: `deadlines.json`, `sync.json`.
public enum JSONFile {
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? DrBarJSON.decoder().decode(T.self, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try DrBarJSON.encoder().encode(value).write(to: url, options: .atomic)
    }
}
