import AppKit
import CoreServices
import DrBarKit
import OSAKit

/// One progress update, ready to send.
struct MailUpdate {
    var paperID: UUID
    var groupID: UUID
    /// The account to send from in Mail; empty for Mail's default.
    var senderAddress: String
    var recipients: [Person]
    /// The thread's subject, without "Re:", as stored on the paper.
    var threadSubject: String
    /// This email's subject, without "Re:": the thread's subject with the time left.
    var subject: String
    var body: String
    /// The timeline image as PNG.
    var image: Data
    var imageName: String
    /// The thread to reply in; `nil` starts a new one.
    var thread: MailThread?

    /// The subject it goes out with: a reply's in a thread already started.
    var sentSubject: String {
        thread == nil ? subject : ProgressSummary.replySubject(subject)
    }
}

/// Sends progress updates to a group of recipients.
///
/// Mail is driven through AppleScript because only Mail's own "reply" fills in the
/// `In-Reply-To` and `References` headers that keep a thread together. Other mail apps get a
/// prepared draft instead, which the user sends. Nothing is ever sent without the user's click.
@MainActor
final class ProgressMail {
    enum Client: Equatable {
        case appleMail
        /// Another default mail app; `nil` when there is none.
        case other(name: String?)
    }

    enum Failure: LocalizedError {
        case automationDenied
        case threadNotFound
        case mailError(String)
        case draftUnavailable

        var errorDescription: String? {
            switch self {
            case .automationDenied:
                String(
                    localized:
                        "DrBar is not allowed to control Mail. Turn it on in System Settings › Privacy & Security › Automation."
                )
            case .threadNotFound:
                String(
                    localized:
                        "The first email of this thread is no longer in Mail's Sent mailbox, perhaps because it was deleted or you changed computers."
                )
            case let .mailError(message):
                String(localized: "Mail reported a problem: \(message)")
            case .draftUnavailable:
                String(localized: "No mail app could open the email.")
            }
        }
    }

    /// Called when Mail reports the Message-ID of a thread's first email, some seconds after sending.
    var onMessageID: ((_ paperID: UUID, _ groupID: UUID, _ subject: String, _ messageID: String) -> Void)?

    private let bridge = MailBridge()
    nonisolated private static let mailBundleID = "com.apple.mail"

    /// The app that opens `mailto:` links.
    var defaultClient: Client {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "mailto:someone@example.org")!)
        else {
            return .other(name: nil)
        }
        if Bundle(url: url)?.bundleIdentifier == Self.mailBundleID {
            return .appleMail
        }
        return .other(
            name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }

    // MARK: Mail

    /// Sends `update` with Mail, as a reply in its thread when there is one.
    /// - Returns: the thread to store on the paper.
    func sendWithMail(_ update: MailUpdate) async throws -> MailThread {
        try await ensureMailIsRunning()
        try await requestAutomationPermission()

        let attachment = try writeMailAttachment(update.image, name: update.imageName)
        // Mail reads the attachment while composing; remove it once that is surely done.
        Task {
            try? await Task.sleep(for: .seconds(120))
            try? FileManager.default.removeItem(at: attachment.deletingLastPathComponent())
        }

        let sentAt = Date()
        let outgoingID: Int32
        // A thread whose first email was a draft in another app has no Message-ID: continue it by subject.
        let message: [MailArgument] = [
            .text(update.senderAddress), .list(update.recipients.map { $0.name.trimmingCharacters(in: .whitespaces) }),
            .list(update.recipients.map(\.address)), .text(update.sentSubject), .text(update.body),
            .text(attachment.path),
        ]
        if let firstID = update.thread?.messageID {
            outgoingID = try await bridge.call("composeReply", [.text(firstID)] + message).number
            guard outgoingID != -1 else { throw Failure.threadNotFound }
        } else {
            outgoingID = try await bridge.call("composeNewMessage", message).number
        }

        // Give Mail a moment to load the attachment.
        try? await Task.sleep(for: .seconds(1.5))
        guard try await bridge.call("sendMessage", [.number(outgoingID)]).isTrue else {
            throw Failure.mailError(String(localized: "The message could not be sent."))
        }

        if var thread = update.thread, thread.messageID != nil {
            thread.lastSentAt = sentAt
            return thread
        }
        // Mail files the message in Sent after a few seconds; look for its Message-ID twice.
        lookUpMessageID(for: update, sentAfter: sentAt.addingTimeInterval(-120))
        return MailThread(
            groupID: update.groupID, subject: update.threadSubject, messageID: nil,
            startedAt: update.thread?.startedAt ?? sentAt, lastSentAt: sentAt)
    }

    private func lookUpMessageID(for update: MailUpdate, sentAfter: Date) {
        guard let address = update.recipients.first?.address else { return }
        Task {
            for delay in [5, 25] {
                try? await Task.sleep(for: .seconds(delay))
                let result = try? await bridge.call(
                    "findSentMessageID", [.text(update.sentSubject), .text(address), .date(sentAfter)]
                ).text
                if let messageID = result, !messageID.isEmpty {
                    onMessageID?(update.paperID, update.groupID, update.threadSubject, messageID)
                    return
                }
            }
        }
    }

    /// Mail must be running to be asked for permission; it is launched in the background.
    private func ensureMailIsRunning() async throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.mailBundleID).isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.mailBundleID) else {
            throw Failure.mailError(String(localized: "Mail is not installed."))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try? await Task.sleep(for: .seconds(2))
    }

    /// Asks "DrBar wants to control Mail" off the main thread, so the prompt never blocks the UI.
    private func requestAutomationPermission() async throws {
        let status = await Task.detached(priority: .userInitiated) { () -> OSStatus in
            let target = NSAppleEventDescriptor(bundleIdentifier: ProgressMail.mailBundleID)
            guard let address = target.aeDesc else { return OSStatus(procNotFound) }
            return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, true)
        }.value
        switch status {
        case noErr: return
        case OSStatus(errAEEventNotPermitted): throw Failure.automationDenied
        default: throw Failure.mailError("OSStatus \(status)")
        }
    }

    /// Mail is sandboxed and can read attachments only from places such as Downloads, so the
    /// image waits in a hidden folder there while Mail composes, and is removed two minutes later.
    /// Should the app quit before that, the next launch removes it.
    private func writeMailAttachment(_ png: Data, name: String) throws -> URL {
        // One folder per email keeps the file name, which Mail shows, without replacing another file.
        let folder = Self.attachmentsFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try png.write(to: url)
        return url
    }

    /// Removes attachments left by a previous run that quit too early.
    static func removeLeftoverAttachments() {
        try? FileManager.default.removeItem(at: attachmentsFolder)
    }

    /// `~/Downloads/.DrBar`, outside the sandbox container, where Mail can see it.
    private static var attachmentsFolder: URL {
        let downloads =
            if let home = getpwuid(getuid())?.pointee.pw_dir {
                URL(fileURLWithPath: String(cString: home)).appending(path: "Downloads", directoryHint: .isDirectory)
            } else {
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
            }
        return downloads.appending(path: ".DrBar", directoryHint: .isDirectory)
    }

    // MARK: Other mail apps

    /// Opens a new email in the default mail app (Outlook, a browser with Gmail…) through a
    /// `mailto:` link with the subject and text filled in, and puts the timeline image on the
    /// clipboard to paste. The user presses Send there. Such a link cannot carry the threading
    /// headers, so later updates are tied to the thread by their "Re:" subject only.
    func openDraft(_ update: MailUpdate) throws {
        guard let url = Self.mailtoURL(update), let image = NSImage(data: update.image) else {
            throw Failure.draftUnavailable
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        guard NSWorkspace.shared.open(url) else { throw Failure.draftUnavailable }
    }

    static func mailtoURL(_ update: MailUpdate) -> URL? {
        MailtoLink.url(to: update.recipients.map(\.address), subject: update.sentSubject, body: update.body)
    }
}

/// What is passed to a handler of the script.
private enum MailArgument: Sendable {
    case text(String)
    /// An AppleScript list of text.
    case list([String])
    case number(Int32)
    case date(Date)

    var descriptor: NSAppleEventDescriptor {
        switch self {
        case let .text(text):
            return NSAppleEventDescriptor(string: text)
        case let .list(strings):
            let list = NSAppleEventDescriptor.list()
            for (index, string) in strings.enumerated() {
                list.insert(NSAppleEventDescriptor(string: string), at: index + 1)
            }
            return list
        case let .number(number):
            return NSAppleEventDescriptor(int32: number)
        case let .date(date):
            return NSAppleEventDescriptor(date: date)
        }
    }
}

/// What a handler of the script returned, read as the app needs it.
private struct MailReply: Sendable {
    var number: Int32
    var isTrue: Bool
    var text: String?
}

/// Runs the handlers of `MailBridge.applescript` one at a time, on a queue of its own, as
/// AppleScript allows, so that however long Mail takes to answer, the interface never waits. The
/// script gives up on Mail after 30 seconds.
private final class MailBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "DrBar.MailBridge", qos: .userInitiated)
    /// Only touched on `queue`.
    private var script: OSAScript?

    func call(_ handler: String, _ arguments: [MailArgument]) async throws -> MailReply {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.run(handler, arguments) })
            }
        }
    }

    private func run(_ handler: String, _ arguments: [MailArgument]) throws -> MailReply {
        let script = try compiled()
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            parameters.insert(argument.descriptor, at: index + 1)
        }
        let event = NSAppleEventDescriptor(
            eventClass: AppleScriptCodes.suite, eventID: AppleScriptCodes.subroutine, targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setDescriptor(
            NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AppleScriptCodes.subroutineName)
        event.setDescriptor(parameters, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error) ?? .null()
        if let error {
            let number = error[OSAScriptErrorNumberKey] as? Int ?? 0
            if number == Int(errAEEventNotPermitted) { throw ProgressMail.Failure.automationDenied }
            throw ProgressMail.Failure.mailError(
                error[OSAScriptErrorMessageKey] as? String ?? "AppleScript error \(number)")
        }
        return MailReply(number: result.int32Value, isTrue: result.booleanValue, text: result.stringValue)
    }

    /// Xcode compiles `MailBridge.applescript` into `MailBridge.scpt` when it copies resources.
    private func compiled() throws -> OSAScript {
        if let script { return script }
        var error: NSDictionary?
        guard let url = Bundle.main.url(forResource: "MailBridge", withExtension: "scpt"),
            let script = OSAScript(contentsOf: url, error: &error)
        else {
            throw ProgressMail.Failure.mailError(
                error?[OSAScriptErrorMessageKey] as? String ?? "MailBridge.scpt is missing")
        }
        self.script = script
        return script
    }
}

/// Four-character codes for calling an AppleScript handler (from OpenScripting's ASRegistry.h).
private enum AppleScriptCodes {
    static let suite = AEEventClass(0x6173_6372)  // 'ascr', kASAppleScriptSuite
    static let subroutine = AEEventID(0x7073_6272)  // 'psbr', kASSubroutineEvent
    static let subroutineName = AEKeyword(0x736E_616D)  // 'snam', keyASSubroutineName
}
