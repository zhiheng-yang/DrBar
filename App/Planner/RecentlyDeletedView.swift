import DrBarKit
import DrBarUI
import SwiftUI

/// What was deleted in the last thirty days, newest first, each with the days it has left, as Notes
/// and Photos keep it: papers and items, and the blocks, milestones, deadlines and to-dos deleted
/// from them. Recover puts one back where it was, a part into its paper or item, which comes back
/// with it if it was deleted too; Delete removes it for good, and so does Delete All for everything.
struct RecentlyDeletedView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Set<UUID> = []

    var body: some View {
        let entries = store.userData.deletedEntries
        let titles = Dictionary(
            (store.userData.papers + store.userData.archive + store.userData.recentlyDeleted.map(\.paper))
                .map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first })
        List(selection: $selection) {
            ForEach(entries) { entry in
                DeletedRow(entry: entry, titles: titles)
                    .tag(entry.id)
                    .swipeActions(edge: .leading) {
                        Button {
                            animated { store.recover([entry.id], undoManager: undoManager) }
                        } label: {
                            Label("Recover", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                    // Not a destructive button, whose row would slide away before the user is asked.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            store.pendingPermanentDeletion = [entry.id]
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Recover") { animated { store.recover(Array(ids), undoManager: undoManager) } }
            Divider()
            Button("Delete…", role: .destructive) { store.pendingPermanentDeletion = ids }
        } primaryAction: { ids in
            animated { store.recover(Array(ids), undoManager: undoManager) }
        }
        .onDeleteCommand { store.pendingPermanentDeletion = selection }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No Recently Deleted Items", systemImage: "trash")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete All…") { store.pendingPermanentDeletion = Set(entries.map(\.id)) }
                    .disabled(entries.isEmpty)
            }
        }
        .onChange(of: entries.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
        .navigationTitle("Recently Deleted")
    }

    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .settle, change)
    }
}

/// A deleted paper or item with its group, or a part of one with the paper or item it was part of
/// and its days; then the days before it goes for good, as Photos counts them.
private struct DeletedRow: View {
    let entry: DeletedEntry
    /// The titles of the papers and items, wherever they are, by id.
    let titles: [UUID: String]
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .lineLimit(1)
                    if let detail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                icon
                    .accessibilityLabel(kind)
            }
            Spacer()
            Text("\(entry.daysLeft(now: store.now)) days left")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .help(Text("Deleted \(entry.deletedAt.formatted(date: .abbreviated, time: .shortened))"))
    }

    private var title: String {
        switch entry {
        case let .paper(deleted):
            deleted.paper.displayTitle
        case let .part(part):
            switch part.content {
            case let .block(block): block.displayName
            case let .milestone(milestone): milestone.displayName
            case let .deadline(deadline, _): deadline.displayName
            case let .todo(todo): todo.title
            }
        }
    }

    /// A paper's or an item's group; a part's paper or item, and when it was.
    private var detail: String? {
        switch entry {
        case let .paper(deleted):
            return deleted.paper.isPaper
                ? String(localized: "Papers")
                : (store.userData.groups.first { $0.id == deleted.paper.groupID } ?? deleted.group)?.displayName
        case let .part(part):
            let when: String? =
                switch part.content {
                case let .block(block): BlockText.range(block)
                case let .milestone(milestone): MilestoneText.day(milestone.day)
                case let .deadline(deadline, _): DeadlineText.localDateTime(deadline.date)
                case .todo: nil
                }
            let parts = [titles[part.paperID], when].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// A block as its bar is drawn, in its color; a diamond for a milestone and a flag for a
    /// deadline, as on the timeline; a page for a paper, its group's symbol for an item.
    @ViewBuilder
    private var icon: some View {
        switch entry {
        case let .paper(deleted):
            Image(systemName: store.userData.symbol(of: deleted.paper, deletedWith: deleted.group))
        case let .part(part):
            switch part.content {
            case let .block(block):
                RoundedRectangle.bar(height: 8)
                    .fill(BlockColor.color(for: block))
                    .frame(width: 16, height: 8)
            case .milestone: Image(systemName: "diamond")
            case .deadline: Image(systemName: "flag")
            case .todo: Image(systemName: "checklist")
            }
        }
    }

    private var kind: Text {
        switch entry {
        case let .paper(deleted): deleted.paper.isPaper ? Text("Paper") : Text("Item")
        case let .part(part):
            switch part.content {
            case .block: Text("Block")
            case .milestone: Text("Milestone")
            case .deadline: Text("Deadline")
            case .todo: Text("To-Do")
            }
        }
    }
}
