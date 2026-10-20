import Foundation

/// A notification to schedule. The app turns `content` into localized text.
public struct PlannedReminder: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        /// `daysBefore` days before a followed deadline.
        case deadline(FollowedDeadline, daysBefore: Int)
        /// 9:00 on the last day of a block that is not done.
        case blockDue(paperTitle: String, block: TimeBlock)
        /// 9:00 on the day of a milestone that is not done.
        case milestoneDue(paperTitle: String, milestone: Milestone)
    }

    /// The object id plus the fire time, so rescheduling never creates duplicates.
    public var id: String
    public var fireDate: Date
    public var content: Content
    /// What a click on the notification opens.
    public var destination: Destination
}

/// Decides which notifications to schedule.
///
/// macOS keeps at most 64 pending notifications per app, so after every sync or edit the app
/// removes all pending ones and schedules only the next `limit`.
public enum ReminderPlanner {
    public static let limit = 60
    /// Block and milestone reminders fire at this hour on their day.
    static let blockReminderHour = 9

    /// - Parameter deadlines: what is followed (`DeadlineRows.followed`); every one but the
    ///   notifications, which there is nothing to do by, is reminded of.
    public static func plan(
        deadlines: [FollowedDeadline], papers: [Paper], settings: AppSettings, now: Date,
        calendar: Calendar = .gregorianLocal, limit: Int = limit
    ) -> [PlannedReminder] {
        guard settings.notificationsEnabled else { return [] }
        var reminders: [PlannedReminder] = []

        for followed in deadlines where !followed.deadline.isEvent && followed.date > now {
            for days in Set(settings.reminderDays) {
                // Whole days on the calendar, so that a change of the clocks between keeps the time.
                guard let fire = calendar.date(byAdding: .day, value: -days, to: followed.date), fire > now else {
                    continue
                }
                reminders.append(
                    PlannedReminder(
                        id: "\(followed.id)@\(Int(fire.timeIntervalSince1970))", fireDate: fire,
                        content: .deadline(followed, daysBefore: days), destination: followed.destination))
            }
        }

        if settings.blockReminders {
            func morning(of day: Day) -> Date? {
                calendar.date(
                    from: DateComponents(year: day.year, month: day.month, day: day.day, hour: blockReminderHour))
            }
            for paper in papers {
                for block in paper.blocks where !block.isDone {
                    guard let fire = morning(of: block.end), fire > now else { continue }
                    reminders.append(
                        PlannedReminder(
                            id: "block|\(block.id.uuidString)@\(Int(fire.timeIntervalSince1970))",
                            fireDate: fire,
                            content: .blockDue(paperTitle: paper.title, block: block),
                            destination: .paper(paper.id)))
                }
                for milestone in paper.milestones where !milestone.isDone {
                    guard let fire = morning(of: milestone.day), fire > now else { continue }
                    reminders.append(
                        PlannedReminder(
                            id: "milestone|\(milestone.id.uuidString)@\(Int(fire.timeIntervalSince1970))",
                            fireDate: fire,
                            content: .milestoneDue(paperTitle: paper.title, milestone: milestone),
                            destination: .paper(paper.id)))
                }
            }
        }

        reminders.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(reminders.prefix(limit))
    }
}
