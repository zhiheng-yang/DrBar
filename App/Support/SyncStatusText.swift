import SwiftUI

/// "Updated 3 hours ago", "Offline — using saved data"…
struct SyncStatusText: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Text(Self.text(for: store))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(String(localized: "Conference data from ccfddl."))
    }

    @MainActor
    static func text(for store: AppStore) -> String {
        switch store.syncActivity {
        case .syncing:
            return String(localized: "Syncing…")
        case .failed(offline: true):
            return String(localized: "Offline — using saved data")
        case .failed(offline: false):
            return String(localized: "Could not update — using saved data")
        case .idle:
            if let date = store.syncState.lastSuccess {
                return String(localized: "Updated \(relative(date, to: store.now))")
            } else if let date = store.syncState.snapshotDate {
                // The snapshot's day is a calendar day, stored as midnight UTC.
                var day = Date.FormatStyle(date: .abbreviated, time: .omitted)
                day.timeZone = .gmt
                return String(localized: "Built-in data from \(date.formatted(day))")
            }
            return String(localized: "Not synced yet")
        }
    }

    static func relative(_ date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}
