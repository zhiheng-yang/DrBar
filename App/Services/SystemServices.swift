import AppKit
import Network
import ServiceManagement

/// Calls back when the network comes back after being unavailable, so a missed sync can run.
final class NetworkMonitor: Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "DrBar.NetworkMonitor", qos: .utility)

    func start(onReconnect: @escaping @Sendable () -> Void) {
        let wasOffline = OfflineFlag()
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                if wasOffline.take() { onReconnect() }
            } else {
                wasOffline.set()
            }
        }
        monitor.start(queue: queue)
    }

    /// Only touched on the monitor's serial queue.
    private final class OfflineFlag: @unchecked Sendable {
        private var value = false
        func set() { value = true }
        func take() -> Bool {
            defer { value = false }
            return value
        }
    }
}

/// Launch at login through `SMAppService`, which starts the app itself: no helper process.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// The setting follows the system, because the user can switch it off in System Settings.
    static var isEnabled: Bool {
        status == .enabled
    }

    static var needsApproval: Bool {
        status == .requiresApproval
    }

    /// Registered, whether or not the user has approved it yet.
    static var isRegistered: Bool {
        isEnabled || needsApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum SystemSettingsLink {
    /// System Settings › Notifications.
    static let notifications = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    /// System Settings › Privacy & Security › Automation.
    static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}
