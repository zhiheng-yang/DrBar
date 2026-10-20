import DrBarKit
import DrBarUI
import SwiftUI

/// The send panel: the group it goes to, the image that will be sent, a message, the optional
/// summary, Cancel and Send. Nothing leaves the Mac until the user presses Send.
struct SendProgressSheet: View {
    let paperID: UUID
    /// Called once Mail has sent the update, not when a draft opens in another mail app.
    var onSent: (RecipientGroup) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general
    @State private var groupID: RecipientGroup.ID?
    @State private var message = ""
    @State private var includeSummary = true
    /// Whether the update tells of the other work the group may hear about, as the thread's last
    /// one did.
    @State private var includesOtherWork = false
    @State private var subject = ""
    @State private var failure: ProgressMail.Failure?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Send Progress")
                .font(.headline)

            if let paper {
                if let group {
                    recipients(of: group)
                    // On a small screen the email scrolls, and Cancel and Send stay in view.
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            preview(for: paper, to: group)
                            subjectField(for: paper, to: group)
                            // The first line of the email, which the inbox shows before it is opened.
                            Text(verbatim: headline(for: paper, to: group))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            messageField
                            Toggle("Include progress summary", isOn: $includeSummary)
                            if includeSummary {
                                addition(summary(for: paper, to: group))
                            }
                            // Only when something is visible to everyone it goes to.
                            if let otherWork = otherWorkText(for: paper, to: group) {
                                Toggle("Include other work", isOn: $includesOtherWork)
                                if includesOtherWork {
                                    addition(otherWork)
                                }
                            }
                            clientNote
                        }
                    }
                    .frame(maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 200)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    missingRecipients(Text("Add a group of recipients in Settings first."))
                }
            }

            HStack {
                Spacer()
                // Once Mail is at work the email goes out, so there is no stopping it then.
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isSendingProgress)
                Button {
                    Task { await send() }
                } label: {
                    if store.isSendingProgress {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 40)
                    } else {
                        Group {
                            if case .appleMail = store.mail.defaultClient {
                                Text("Send")
                            } else {
                                Text("Open Draft")
                            }
                        }
                        .frame(minWidth: 40)
                    }
                }
                // ⌘Return, not Return alone: an email cannot be unsent.
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: TimelineImage.width + 2 * Theme.Space.xl)
        .interactiveDismissDisabled(store.isSendingProgress)
        .onAppear {
            guard let paper else { return }
            groupID = Self.likelyGroup(for: paper, among: store.userData.mail.groups)
            subject = defaultSubject(for: paper, to: group)
            includesOtherWork = group.flatMap { paper.thread(for: $0.id) }?.includesOtherWork ?? false
        }
        .onChange(of: groupID) { oldID, _ in
            // A subject still as it was proposed follows the language of the new group.
            guard let paper else { return }
            let old = store.userData.mail.groups.first { $0.id == oldID }
            if subject == defaultSubject(for: paper, to: old) {
                subject = defaultSubject(for: paper, to: group)
            }
            includesOtherWork = group.flatMap { paper.thread(for: $0.id) }?.includesOtherWork ?? false
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { failure in
            switch failure {
            case .automationDenied:
                Button("Open System Settings") { NSWorkspace.shared.open(SystemSettingsLink.automation) }
                Button("OK", role: .cancel) {}
            case .threadNotFound:
                Button("Start a New Thread") {
                    if let group {
                        store.forgetThread(with: group.id, paperID: paperID)
                    }
                    Task { await send() }
                }
                Button("Cancel", role: .cancel) {}
            default:
                Button("OK", role: .cancel) {}
            }
        } message: { failure in
            Text(failure.localizedDescription)
        }
    }

    private var paper: Paper? {
        store.userData.papers.first { $0.id == paperID }
    }

    private var group: RecipientGroup? {
        store.userData.mail.groups.first { $0.id == groupID }
    }

    private var canSend: Bool {
        guard !store.isSendingProgress, let paper, let group, !group.recipients.isEmpty else { return false }
        return paper.thread(for: group.id) != nil || !subject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The group the last update of the paper went to, or else the first that has an address.
    static func likelyGroup(for paper: Paper, among groups: [RecipientGroup]) -> RecipientGroup.ID? {
        let latest = paper.threads
            .filter { thread in groups.contains { $0.id == thread.groupID } }
            .max { ($0.lastSentAt ?? $0.startedAt) < ($1.lastSentAt ?? $1.startedAt) }
        return latest?.groupID ?? groups.first { !$0.recipients.isEmpty }?.id ?? groups.first?.id
    }

    // MARK: Fields

    private func recipients(of group: RecipientGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Picker("To", selection: $groupID) {
                    ForEach(store.userData.mail.groups) { group in
                        Text(group.displayName).tag(Optional(group.id))
                    }
                }
                .fixedSize()
                if !group.recipients.isEmpty {
                    Text(group.recipients.map(\.displayName).formatted(.list(type: .and)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(group.recipients.map(\.addressLine).joined(separator: ", "))
                }
            }
            if group.recipients.isEmpty {
                missingRecipients(Text("Add people with an email address to \(group.displayName) in Settings first."))
            }
        }
    }

    private func missingRecipients(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                text
            } icon: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
            }
            .foregroundStyle(.orange)
            Spacer()
            Button("Open Settings") {
                settingsTab = .email
                openSettings()
                NSApp.activate()
            }
        }
    }

    /// The image exactly as it will be attached.
    private func preview(for paper: Paper, to group: RecipientGroup) -> some View {
        TimelineImageView(content: content(for: paper, to: group, withOtherWork: includesOtherWork))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Preview of the timeline image"))
    }

    @ViewBuilder
    private func subjectField(for paper: Paper, to group: RecipientGroup) -> some View {
        if let thread = paper.thread(for: group.id) {
            LabeledContent("Subject") {
                Text(verbatim: ProgressSummary.replySubject(thread.subject + subjectSuffix(for: paper, to: group)))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                TextField("Subject", text: $subject)
                Text(verbatim: subjectSuffix(for: paper, to: group))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Message")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $message)
                .font(.body)
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
    }

    /// Text the email adds below the message, in gray, as it will read.
    private func addition(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var clientNote: some View {
        switch store.mail.defaultClient {
        case .appleMail:
            Text("Sent with Mail as a reply in the same thread, and kept in your Sent mailbox.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .other(name):
            Text(
                "DrBar opens a new email in \(name ?? String(localized: "your mail app")) with the text filled in and copies the image, so you can paste it (⌘V) and press Send there. Later updates continue the thread by subject, which Gmail may not group."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Content

    private func content(
        for paper: Paper, to group: RecipientGroup, withOtherWork: Bool = false
    ) -> TimelineImage.Content {
        TimelineImage.content(
            for: paper, overview: store.overview(for: paper), group: group, people: store.userData.people,
            otherWork: withOtherWork ? otherWork(for: paper, to: group) : [], now: store.now)
    }

    /// The other papers and items that everyone the update goes to may hear about.
    private func otherWork(for paper: Paper, to group: RecipientGroup) -> [(paper: Paper, deadlines: PaperDeadlines)] {
        store.userData.work(visibleTo: group.recipients, besides: paper.id, catalog: store.catalog, now: store.now)
    }

    private func otherWorkText(for paper: Paper, to group: RecipientGroup) -> String? {
        ProgressSummary.otherWork(
            otherWork(for: paper, to: group), language: group.language, hidesBufferBlocks: group.hidesBufferBlocks,
            now: store.now)
    }

    private func defaultSubject(for paper: Paper, to group: RecipientGroup?) -> String {
        MailStrings(group?.language ?? .english).defaultSubject(paperTitle: paper.title)
    }

    /// The stage and the time left to the next deadline, which every update adds to the thread's
    /// subject.
    private func subjectSuffix(for paper: Paper, to group: RecipientGroup) -> String {
        let current = ProgressSummary.currentBlock(
            of: paper, hidesBufferBlocks: group.hidesBufferBlocks, today: Day(store.now))
        return ProgressSummary.subjectSuffix(
            store.overview(for: paper).deadlines, current: current, language: group.language, now: store.now)
    }

    private func headline(for paper: Paper, to group: RecipientGroup) -> String {
        ProgressSummary.headline(
            paper: paper, status: content(for: paper, to: group).status, recipients: Set(group.people.map(\.id)),
            lastUpdate: paper.thread(for: group.id)?.lastSentAt, language: group.language,
            hidesBufferBlocks: group.hidesBufferBlocks, now: store.now)
    }

    private func summary(for paper: Paper, to group: RecipientGroup) -> String {
        ProgressSummary.text(
            paper: paper, deadlines: store.overview(for: paper).deadlines, language: group.language,
            hidesBufferBlocks: group.hidesBufferBlocks, people: store.userData.people, now: store.now)
    }

    private func send() async {
        guard canSend, let paper, let group else { return }
        store.isSendingProgress = true
        defer { store.isSendingProgress = false }
        // As it is now: the sheet stays open while Mail works, and may change meanwhile.
        let includesOtherWork = includesOtherWork
        guard let png = TimelineImage.png(content(for: paper, to: group, withOtherWork: includesOtherWork)) else {
            failure = .mailError(String(localized: "The timeline image could not be created."))
            return
        }
        let mail = store.userData.mail
        let thread = paper.thread(for: group.id)
        let threadSubject = thread?.subject ?? subject.trimmingCharacters(in: .whitespaces)
        let update = MailUpdate(
            paperID: paper.id, groupID: group.id,
            senderAddress: mail.senderAddress.trimmingCharacters(in: .whitespaces), recipients: group.recipients,
            threadSubject: threadSubject, subject: threadSubject + subjectSuffix(for: paper, to: group),
            body: ProgressSummary.body(
                headline: headline(for: paper, to: group), message: message,
                summary: includeSummary ? summary(for: paper, to: group) : nil,
                otherWork: includesOtherWork ? otherWorkText(for: paper, to: group) : nil, signature: mail.signature),
            image: png, imageName: Self.imageName(for: paper, now: store.now), thread: thread)
        do {
            switch store.mail.defaultClient {
            case .appleMail:
                var sent = try await store.mail.sendWithMail(update)
                sent.includesOtherWork = includesOtherWork
                store.keepThread(sent, paperID: paper.id)
                onSent(group)
            case .other:
                // Whether the draft goes out is up to the user; the thread keeps only its subject.
                try store.mail.openDraft(update)
                var kept = thread ?? MailThread(groupID: group.id, subject: threadSubject, startedAt: Date())
                kept.includesOtherWork = includesOtherWork
                store.keepThread(kept, paperID: paper.id)
            }
            dismiss()
        } catch let error as ProgressMail.Failure {
            failure = error
        } catch {
            failure = .mailError(error.localizedDescription)
        }
    }

    /// "DrBar Efficient Video Diffusion 2026-10-12.png"
    static func imageName(for paper: Paper, now: Date) -> String {
        let title = paper.title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(
            separator: "-")
        return "DrBar \(title.prefix(40)) \(Day(now)).png"
    }
}

extension ProgressMail.Failure {
    var title: String {
        switch self {
        case .automationDenied: String(localized: "Mail Access Is Off")
        case .threadNotFound: String(localized: "Thread Not Found")
        case .mailError, .draftUnavailable: String(localized: "Could Not Send")
        }
    }
}

#if DEBUG
#Preview("Send Progress") {
    DemoPreview {
        if let paper = AppStore.shared.userData.papers.first {
            SendProgressSheet(paperID: paper.id) { _ in }
        }
    }
}
#endif
