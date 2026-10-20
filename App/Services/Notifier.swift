import AppKit
import DrBarKit
import DrBarUI
import UserNotifications

/// Schedules reminders and shows date-change alerts.
///
/// Permission is requested only when the user turns reminders on, never at launch. The reminder
/// on a block's last day or a milestone's day offers Mark as Done, as Reminders does, and so does
/// one of a deadline that a single paper or item has open and that is ticked off by itself.
@MainActor
final class Notifier: NSObject {
    /// What a reminder can mark as done.
    enum Work: Codable, Sendable {
        case block(UUID, paper: UUID)
        case milestone(UUID, paper: UUID)
        /// A deadline by its `PaperDeadline.id`.
        case deadline(String, paper: UUID)
    }

    /// Called when the user clicks a notification.
    var onOpen: ((Destination) -> Void)?
    /// Called when the user marks the work of a reminder as done from the notification.
    var onMarkDone: ((Work) -> Void)?
    private var center: UNUserNotificationCenter { .current() }
    /// What is pending, and the time zone it was worded in; `nil` until the first call, which always
    /// replaces what an earlier run left pending.
    private var scheduled: (reminders: [PlannedReminder], timeZone: TimeZone)?

    func activate() {
        center.delegate = self
        let markDone = UNNotificationAction(identifier: Self.markDoneAction, title: String(localized: "Mark as Done"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.workCategory, actions: [markDone], intentIdentifiers: [])
        ])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Removes every pending and delivered notification.
    func removeAll() {
        scheduled = ([], .current)
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Replaces every pending reminder with `reminders` (at most 60, see `ReminderPlanner`), unless
    /// those pending are the same and would read the same: a name, a time, or what Mark as Done
    /// does may have changed while the moment stayed.
    func reschedule(_ reminders: [PlannedReminder]) {
        let zone = TimeZone.current
        if let scheduled, scheduled.reminders == reminders, scheduled.timeZone == zone { return }
        scheduled = (reminders, zone)
        center.removeAllPendingNotificationRequests()
        for reminder in reminders {
            let content = content(for: reminder)
            // With the time zone in the components the trigger is an absolute moment, so a
            // deadline reminder still fires on time after the Mac changes time zone.
            var parts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            parts.timeZone = .current
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)) {
                [weak self] error in
                guard error != nil else { return }
                // Not added, as while notifications are off: the next pass adds them again.
                Task { @MainActor in self?.scheduled = nil }
            }
        }
    }

    /// "ICLR 2027: Paper submission changed" with "09-25 → 10-01 (AoE)", delivered right away.
    func notify(changes: [DeadlineChange]) {
        for change in changes {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(change.item.fullTitle): \(change.item.kind.localizedName) changed")
            content.body = "\(change.compact.old) → \(change.compact.new) (\(change.item.timeZone))"
            content.sound = .default
            let item = change.item
            content.userInfo = Self.userInfo(
                opening: .deadline(.conference(series: item.seriesKey, edition: item.editionID, round: item.roundID)))
            let id = "change|\(change.item.id)|\(change.newText)"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    private func content(for reminder: PlannedReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = Self.userInfo(opening: reminder.destination)
        switch reminder.content {
        case let .deadline(followed, days):
            let name = followed.title
            let what = followed.deadline.name
            content.title =
                days == 1
                ? String(localized: "\(name): \(what) tomorrow")
                : String(localized: "\(name): \(what) in \(days) days")
            let date = DeadlineText.localDateTime(followed.date)
            let zone = followed.deadline.timeZone
            // One entered in local time needs no other.
            content.body =
                zone == TimeZone.current.identifier
                ? date : "\(date) (\(SharedText.localTime)) · \(DeadlineText.displayTimeZone(zone))"
            if let paperID = followed.paperID, followed.deadline.completion == .tick {
                content.offer(.deadline(followed.id, paper: paperID))
            }
        case let .blockDue(paperTitle, block):
            content.title = String(localized: "Last day of \(block.displayName)")
            content.body = String(localized: "\(paperTitle): mark the block done or adjust the plan.")
            if case let .paper(paperID) = reminder.destination {
                content.offer(.block(block.id, paper: paperID))
            }
        case let .milestoneDue(paperTitle, milestone):
            content.title = String(localized: "Due today: \(milestone.displayName)")
            content.body = String(localized: "\(paperTitle): mark the milestone done or move it.")
            if case let .paper(paperID) = reminder.destination {
                content.offer(.milestone(milestone.id, paper: paperID))
            }
        }
        return content
    }

    /// The destination and the work travel in the notification as JSON.
    nonisolated fileprivate static let destinationKey = "destination"
    nonisolated fileprivate static let workKey = "work"
    nonisolated fileprivate static let workCategory = "work"
    nonisolated private static let markDoneAction = "markDone"

    private static func userInfo(opening destination: Destination) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(destination) else { return [:] }
        return [destinationKey: data]
    }
}

extension UNMutableNotificationContent {
    /// Shows Mark as Done for `work`.
    fileprivate func offer(_ work: Notifier.Work) {
        guard let data = try? JSONEncoder().encode(work) else { return }
        categoryIdentifier = Notifier.workCategory
        userInfo[Notifier.workKey] = data
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Banners also appear while DrBar is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking a notification opens the conference or the paper; Mark as Done marks the block,
    /// the milestone or the deadline done without opening anything.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case Self.markDoneAction:
            guard let data = userInfo[Self.workKey] as? Data,
                let work = try? JSONDecoder().decode(Work.self, from: data)
            else { return }
            await MainActor.run { onMarkDone?(work) }
        case UNNotificationDefaultActionIdentifier:
            guard let data = userInfo[Self.destinationKey] as? Data,
                let destination = try? JSONDecoder().decode(Destination.self, from: data)
            else { return }
            await MainActor.run { onOpen?(destination) }
        default:
            break
        }
    }
}
