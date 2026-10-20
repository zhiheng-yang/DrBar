import DrBarKit
import DrBarUI
import SwiftUI

/// What has been put away: papers and items with everything they had, under their groups, until
/// they are moved back. A double click opens one as it was; swiping right moves it back, left
/// deletes it, as in Mail.
struct ArchiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Set<UUID> = []

    var body: some View {
        List(selection: $selection) {
            ForEach(sections, id: \.groupID) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        ArchivedRow(item: item)
                            .tag(item.id)
                            .swipeActions(edge: .leading) {
                                Button {
                                    animated { store.unarchive([item.id], undoManager: undoManager) }
                                } label: {
                                    Label("Move Back", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    animated { store.deletePaper(item.id, undoManager: undoManager) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Open") { store.plannerSelection = .paper(id) }
            }
            Button("Move Back") { animated { store.unarchive(Array(ids), undoManager: undoManager) } }
            Divider()
            Button("Delete", role: .destructive) {
                animated { store.delete(Array(ids), undoManager: undoManager) }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                store.plannerSelection = .paper(id)
            }
        }
        .overlay {
            if store.userData.archive.isEmpty {
                ContentUnavailableView("No Archived Items", systemImage: "archivebox")
            }
        }
        .navigationTitle("Archive")
    }

    /// The papers and each group's items, newest first, as the sidebar orders the groups; known by
    /// the group, as two groups may have the same name.
    private var sections: [(groupID: UUID?, title: String, items: [Paper])] {
        let archive = store.userData.archive.sorted {
            ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast)
        }
        return store.userData.groupOrder.compactMap { groupID in
            let items = archive.filter { $0.groupID == groupID }
            return items.isEmpty ? nil : (groupID, store.groupName(groupID), items)
        }
    }

    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .settle, change)
    }
}

/// An archived paper or item: its title, where it was aimed, and when it was put away.
private struct ArchivedRow: View {
    let item: Paper
    @Environment(AppStore.self) private var store

    var body: some View {
        let aim = store.overview(for: item).deadlines.displayTitle
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(1)
                Text(
                    [aim, item.archivedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }]
                        .compactMap { $0 }.joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } icon: {
            Image(systemName: store.userData.symbol(of: item))
        }
        .padding(.vertical, 2)
    }
}
