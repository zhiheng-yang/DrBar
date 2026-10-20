import DrBarKit
import SwiftUI

/// VoiceOver labels and dates for deadline rows. Exact dates and times appear only in hover cards
/// and in the details view; the lists show time as length.
public enum DeadlineText {
    /// "CVPR 2027, Paper submission November 17, 35 days left"
    public static func spoken(_ row: DeadlineRow, now: Date) -> String {
        let title = row.fullTitle
        switch row.state {
        case .scheduled:
            guard let next = row.nextDeadline(after: now) else { return "\(title), \(SharedText.passed)" }
            let kind = next.kind.localizedName
            let date = next.date.formatted(.dateTime.month(.wide).day())
            let left = CountdownText.spoken(next.date.timeIntervalSince(now))
            return String(
                localized: "\(title), \(kind) \(date), \(left)", bundle: .module,
                comment: "VoiceOver label of a deadline row")
        case .notAnnounced:
            return "\(title), \(SharedText.notAnnounced)"
        case .unreadable:
            return "\(title), \(reason(row))"
        }
    }

    /// Only conference rows can be unreadable; their time zones are ccfddl's.
    static func reason(_ row: DeadlineRow) -> String {
        DeadlineTimeZone.ccf(row.timeZone) == nil ? SharedText.unrecognizedTimeZone : SharedText.unreadable
    }

    /// "Due Tue 2 Feb", for a deadline without a name.
    public static func due(_ date: Date) -> String {
        String(localized: "Due \(localDate(date))", bundle: .module, comment: "A deadline without a name")
    }

    /// "Tue 2 Feb" in the user's time zone and language.
    private static func localDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Tue 17 Nov, 12:59" in the user's time zone and language.
    public static func localDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// The date and time in another time zone, e.g. the conference's own.
    public static func dateTime(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "Mon, Nov 16 23:59 UTC-12": the moment in the time zone it is given in, unless that is
    /// local time on its day.
    public static func ownTime(_ date: Date, _ raw: String) -> String? {
        guard let zone = DeadlineTimeZone.custom(raw),
            zone.secondsFromGMT(for: date) != TimeZone.current.secondsFromGMT(for: date)
        else { return nil }
        return "\(dateTime(date, in: zone)) \(displayTimeZone(raw))"
    }

    /// `UTC-12`, or for a deadline of a paper's own entered in local time, the zone's localized
    /// name.
    public static func displayTimeZone(_ raw: String) -> String {
        guard raw.contains("/"), let zone = TimeZone(identifier: raw) else { return raw }
        return zone.localizedName(for: .shortGeneric, locale: .autoupdatingCurrent) ?? raw
    }
}

/// What paper rows say, and VoiceOver labels for them.
public enum PaperText {
    /// The line under a paper's name: "CVPR 2027", or "Due Tue 10 Nov", or why there is no
    /// deadline.
    public static func subtitle(overview: PaperOverview) -> String? {
        if overview.deadlineNotAnnounced { return SharedText.deadlineNotAnnounced }
        return overview.deadlines.displayTitle
    }

    /// "Video Diffusion, behind, now Writing, CVPR 2027, next Abstract registration November 10, 29
    /// days left"
    public static func spoken(title: String, overview: PaperOverview, now: Date) -> String {
        var parts = [title]
        if overview.status == .behind || overview.status == .conflict {
            parts.append(overview.status.localizedDescription)
        }
        if let current = overview.currentBlock, current.contains(Day(now)) {
            parts.append(
                String(
                    localized: "now \(current.displayName)", bundle: .module,
                    comment: "VoiceOver: the current time block"))
        }
        if let title = overview.deadlines.conference?.title {
            parts.append(title)
        }
        if let next = overview.deadlines.next(after: now), let date = next.date {
            let day = date.formatted(.dateTime.month(.wide).day())
            let left = CountdownText.spoken(date.timeIntervalSince(now))
            parts.append(
                String(
                    localized: "next \(next.name) \(day), \(left)", bundle: .module,
                    comment: "VoiceOver: the next deadline of a paper"))
        }
        return parts.joined(separator: ", ")
    }
}

/// When and where a conference meets, for rows and tooltips.
public enum MeetingText {
    /// "Jun 20 – 25", or a single day. The days are the venue's own, so no time zone applies.
    public static func dates(_ meeting: MeetingDates) -> String {
        let calendar = Calendar.gregorian(in: .gmt)
        let start = meeting.start.startDate(calendar: calendar)
        guard meeting.end > meeting.start else {
            return start.formatted(
                Date.FormatStyle(calendar: calendar, timeZone: .gmt).month(.abbreviated).day())
        }
        let end = meeting.end.startDate(calendar: calendar)
        return (start..<end).formatted(
            Date.IntervalFormatStyle(calendar: calendar, timeZone: .gmt).month(.abbreviated).day())
    }

    /// "Marrakesh, Morocco 🇲🇦": a place with the flags of its countries, those of the whole place
    /// where it is shortened to its city, or else those it names.
    public static func place(_ place: String, flags: String? = nil) -> String {
        let flags = flags ?? CountryFlags.flags(in: place)
        return flags.isEmpty ? place : "\(place) \(flags)"
    }

    /// "Seattle 🇺🇸 · Jun 20 – 25", whichever parts are known.
    public static func summary(place: String?, flags: String? = nil, meeting: MeetingDates?) -> String? {
        let parts = [place.map { Self.place($0, flags: flags) }, meeting.map { dates($0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Texts about a time block, for tooltips and VoiceOver.
public enum BlockText {
    /// "Writing · 25 Oct – 7 Nov · 14 days · not done · with Sam Lee"
    public static func help(_ block: TimeBlock, name: String, people: [Person] = []) -> String {
        let state =
            block.isDone
            ? String(localized: "done", bundle: .module, comment: "Time block state")
            : String(localized: "not done", bundle: .module, comment: "Time block state")
        var parts = [name, range(block), days(block.length), state]
        if !people.isEmpty {
            let names = people.map(\.displayName).formatted(.list(type: .and))
            parts.append(String(localized: "with \(names)", bundle: .module, comment: "Who works on a block"))
        }
        return parts.joined(separator: " · ")
    }

    /// "25 Oct – 7 Nov"
    public static func range(_ block: TimeBlock) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        let start = block.start.startDate().formatted(style)
        let end = block.end.startDate().formatted(style)
        return "\(start) – \(end)"
    }

    public static func days(_ count: Int) -> String {
        String(localized: "\(count) days", bundle: .module, comment: "Length of a time block")
    }
}

public enum MilestoneText {
    /// "Internal deadline · 1 Nov · not done"
    public static func help(_ milestone: Milestone) -> String {
        let state =
            milestone.isDone
            ? String(localized: "done", bundle: .module, comment: "Time block state")
            : String(localized: "not done", bundle: .module, comment: "Time block state")
        return [milestone.displayName, day(milestone.day), state].joined(separator: " · ")
    }

    /// "1 Nov"
    public static func day(_ day: Day) -> String {
        day.startDate().formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Days counted from today, as an axis labelled with them shows them: "Today", "+12", "−3". The
/// sign sets them apart from the days of the month, without a unit to read.
public enum RelativeDayText {
    public static func label(_ days: Int) -> String {
        if days == 0 { return SharedText.today }
        return (days > 0 ? "+" : "−") + abs(days).formatted()
    }

    /// "+12 – +25": the days a block runs, counted from `today`.
    public static func range(_ block: TimeBlock, today: Day) -> String {
        "\(label(today.days(to: block.start))) – \(label(today.days(to: block.end)))"
    }
}

/// Remaining time as text, for the "days" menu bar style, the Conferences page, cards and
/// VoiceOver; the timelines show time as length.
public enum CountdownText {
    /// `35d`, or `16h33m` under a day.
    public static func short(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        if s >= 86_400 { return "\(s / 86_400)d" }
        return "\(s / 3600)h\(s % 3600 / 60)m"
    }

    /// "35 days", or "16 hours" under a day, in the user's language: the time left on its own.
    public static func amount(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 86_400 ? [.day] : seconds >= 3600 ? [.hour] : [.minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: max(seconds, 0)) ?? ""
    }

    /// "35 days left", or "16 hours, 33 minutes left" under a day, in the user's language.
    public static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 86_400 ? [.day] : [.hour, .minute]
        formatter.maximumUnitCount = seconds >= 86_400 ? 1 : 2
        let amount = formatter.string(from: max(seconds, 0)) ?? ""
        return String(
            localized: "\(amount) left", bundle: .module, comment: "Time left until a deadline, e.g. 35 days left")
    }
}

/// How many papers a conference takes, as ccfddl collects it.
public enum AcceptanceText {
    /// "Acceptance 23.4% (2025)"
    public static func short(_ rate: AcceptanceRate) -> String {
        String(
            localized: "Acceptance \(percent(rate.rate)) (\(String(rate.year)))", bundle: .module,
            comment: "The latest acceptance rate of a conference and its year")
    }

    /// "23.4%"
    public static func percent(_ rate: Double) -> String {
        rate.formatted(.percent.precision(.fractionLength(1)))
    }

    /// "3,032 of 12,957", where both are known.
    public static func counts(_ rate: AcceptanceRate) -> String? {
        guard let accepted = rate.accepted, let submitted = rate.submitted else { return nil }
        return String(
            localized: "\(accepted) of \(submitted)", bundle: .module,
            comment: "Papers accepted of those submitted, e.g. 3,032 of 12,957")
    }
}
