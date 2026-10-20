import DrBarKit
import DrBarUI
import SwiftUI

/// What a paper or an item aims at, as a compact menu button: the conference edition a paper will
/// be submitted to ("CVPR 2027 ⌄"), or else its main deadline of its own ("Due Sun 15 Nov ⌄").
/// The menu chooses the conference and its round, and adds and edits deadlines of its own.
struct TargetButton: View {
    let paper: Paper
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var showingBrowser = false
    /// The own deadline whose editor is open at the button.
    @State private var editingDeadline: UUID?

    var body: some View {
        let deadlines = store.overview(for: paper).deadlines
        Menu {
            if paper.isPaper {
                Button(target == nil ? "Choose Conference…" : "Change Conference…") { showingBrowser = true }
            }
            if let target, let (_, edition) = store.catalog.edition(series: target.series, year: target.year),
                edition.rounds.count > 1
            {
                Picker("Round", selection: roundBinding(target)) {
                    // A submitted paper keeps to the round it went to, once that is fixed.
                    if !(paper.isPaper && paper.stage.isSubmitted) || target.round == nil {
                        Text("Next upcoming round").tag(String?.none)
                    }
                    ForEach(edition.rounds) { round in
                        Text(roundTitle(round, count: edition.rounds.count)).tag(Optional(round.id))
                    }
                }
            }
            if target == nil, let main = deadlines.main?.ownID {
                Button("Edit Deadline…") { editingDeadline = main }
            }
            Button(target == nil && deadlines.all.isEmpty ? "Set Deadline…" : "Add Deadline…") {
                editingDeadline = store.addDeadline(to: paper.id, undoManager: undoManager)
            }
            if target != nil {
                Divider()
                Button("Remove Conference") {
                    store.removeConference(of: paper.id, undoManager: undoManager)
                }
            }
        } label: {
            Label(summary(deadlines), systemImage: target == nil && deadlines.all.isEmpty ? "flag" : "flag.fill")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(help(deadlines))
        .sheet(isPresented: $showingBrowser) {
            // A sheet has an undo manager of its own, which goes with it.
            TargetBrowser(paperID: paper.id, undoManager: undoManager)
                .environment(store)
        }
        .popover(isPresented: isEditing, arrowEdge: .bottom) {
            if let editingDeadline {
                DeadlineEditor(paperID: paper.id, id: editingDeadline) { self.editingDeadline = nil }
                    .environment(store)
            }
        }
    }

    private var target: Paper.Target? {
        paper.target
    }

    private var isEditing: Binding<Bool> {
        Binding(get: { editingDeadline != nil }, set: { if !$0 { editingDeadline = nil } })
    }

    /// "CVPR 2027", with the round once one is fixed; else the main deadline's name or when it is
    /// due; else "No deadline".
    private func summary(_ deadlines: PaperDeadlines) -> String {
        if let target {
            guard let conference = deadlines.conference else {
                // An edition the catalog does not have, or not yet.
                return "\(store.catalog.series(withKey: target.series)?.title ?? target.series) \(String(target.year))"
            }
            return target.round == nil ? conference.title : conference.fullTitle
        }
        return deadlines.displayTitle ?? String(localized: "No deadline")
    }

    /// The deadlines still ahead in local time, then the time zone they are given in.
    private func help(_ deadlines: PaperDeadlines) -> String {
        guard target != nil || !deadlines.all.isEmpty else {
            return paper.isPaper
                ? String(localized: "Choose where this paper will be submitted")
                : String(localized: "Set when this is due")
        }
        var lines = deadlines.upcoming(after: store.now).compactMap { deadline in
            deadline.date.map { "\(deadline.name): \(DeadlineText.localDateTime($0))" }
        }
        if deadlines.main.map({ $0.date == nil }) == true {
            lines.append(SharedText.deadlineNotAnnounced)
        }
        if let zone = deadlines.conference?.timeZone ?? deadlines.main?.timeZone, !lines.isEmpty {
            lines.append(DeadlineText.displayTimeZone(zone))
        }
        return lines.joined(separator: "\n")
    }

    private func roundTitle(_ round: ConferenceRound, count: Int) -> String {
        let label = round.label(roundCount: count) ?? ""
        guard let comment = round.comment, comment != label else { return label }
        return "\(label) – \(comment.prefix(60))"
    }

    private func roundBinding(_ target: Paper.Target) -> Binding<String?> {
        Binding(
            get: { target.round },
            set: {
                store.setTarget(
                    Paper.Target(series: target.series, year: target.year, round: $0), of: paper.id,
                    undoManager: undoManager)
            })
    }
}

/// The editor of a deadline of a paper's or an item's own, wherever it opens: at the target
/// button, at its flag on the timeline or at its row in the list.
struct DeadlineEditor: View {
    let paperID: UUID
    let id: UUID
    /// Closes the popover once the deadline is deleted.
    let close: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let paper = store.userData.papers.first(where: { $0.id == paperID }),
            let binding = store.deadlineBinding(id, of: paperID)
        {
            let deadlines = store.overview(for: paper).deadlines
            let resolved = deadlines.all.first { $0.ownID == id }
            CustomDeadlineForm(
                deadline: binding, prompt: prompt(paper, isMain: resolved?.completion == .submission),
                isDone: resolved.flatMap { resolved in
                    resolved.completion == .tick
                        ? Binding(
                            get: { resolved.isDone },
                            set: { isDone in
                                withAnimation(reduceMotion ? nil : .glide) {
                                    store.setDone(isDone, of: resolved, in: paperID, undoManager: undoManager)
                                }
                            })
                        : nil
                },
                isDoneByStage: resolved?.isDoneByStage ?? false,
                makeMain: deadlines.canChooseMain && deadlines.main?.ownID != id
                    ? { store.makeMainDeadline(id, of: paperID, undoManager: undoManager) } : nil,
                delete: {
                    close()
                    store.deleteDeadline(id, undoManager: undoManager)
                })
        }
    }

    /// An example of what such a deadline is called.
    private func prompt(_ paper: Paper, isMain: Bool) -> Text {
        if !paper.isPaper { return Text("e.g. Letters of recommendation") }
        return isMain ? Text("e.g. NeurIPS 2026 Workshop on …") : Text("e.g. Camera-ready")
    }
}
