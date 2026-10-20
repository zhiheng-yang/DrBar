import DrBarKit
import SwiftUI

extension EnvironmentValues {
    /// Whether the axes are labelled with dates, with the days from today or with both, and the
    /// way to change it from an axis.
    @Entry public var axisLabels: Binding<AppSettings.AxisLabels> = .constant(.dates)
}

extension Binding where Value == AppSettings.AxisLabels {
    /// Whether the axes show the dates, or else the days from today, as a checkbox turns them on
    /// and off; the last one shown stays.
    public func shows(dates: Bool) -> Binding<Bool> {
        Binding<Bool>(
            get: { dates ? wrappedValue.showsDates : wrappedValue.showsDays },
            set: { isOn in
                let current = wrappedValue
                let shown = dates ? (isOn, current.showsDays) : (current.showsDates, isOn)
                if shown.0 || shown.1 {
                    wrappedValue = .showing(dates: shown.0, days: shown.1)
                }
            })
    }
}

/// The top of a timeline: the months, or the quarters with the year at January when zoomed far
/// out; the day each week starts on where there is room, or each day over its middle, with its
/// weekday where days are wide enough; and "Today". The finer labels are quieter than the months.
/// Labelled with the days from today instead, it counts them every day, week or few weeks, as there
/// is room; labelled with both, each date has its days from today under it. Each label tells its
/// date on hover, and the menu of the axis turns either on or off.
///
/// An axis moved away from today shows, with `goToToday`, a small "Today" on the side where today
/// lies, which brings it back; so does a double click. While today is out of sight, or no month
/// is named, the month at the left is named there, with its year when that is not this one.
public struct AxisHeader: View {
    public var axis: TimeAxis
    public let now: Date
    public var todayLabel: String
    /// The progress email's image uses the email language rather than the system's.
    public var locale: Locale
    public var goToToday: (() -> Void)?
    @Environment(\.axisLabels) private var labels
    private let calendar = Calendar.gregorianLocal

    public init(
        axis: TimeAxis, now: Date, todayLabel: String = SharedText.today, locale: Locale = .autoupdatingCurrent,
        goToToday: (() -> Void)? = nil
    ) {
        self.axis = axis
        self.now = now
        self.todayLabel = todayLabel
        self.locale = locale
        self.goToToday = goToToday
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = TickScale(
                axis: axis, width: width, dayCountWidth: labels.wrappedValue == .both ? widestDayCount : 0)
            let today = todaySpan(width: width, scale: scale)
            let way = wayToToday
            // Leave room for "Today", the way back to it and the right edge: for a label drawn
            // just after `x`, and for one that takes up `span`.
            let fits = { (x: CGFloat) in
                (today.map { x <= $0.lowerBound - Self.beforeToday || x >= $0.upperBound + Self.afterToday } ?? true)
                    && x < width - Self.edgeRoom
                    && (way != .earlier || x > Self.earlierWayRoom) && (way != .later || x < width - Self.laterWayRoom)
            }
            let isClear = { (span: ClosedRange<CGFloat>) in
                span.lowerBound >= 0 && span.upperBound <= width
                    && (today.map { span.upperBound <= $0.lowerBound - 4 || span.lowerBound >= $0.upperBound + 4 }
                        ?? true)
                    && (way != .earlier || span.lowerBound > Self.earlierWayRoom)
                    && (way != .later || span.upperBound < width - Self.laterWayRoom)
            }
            ZStack(alignment: .topLeading) {
                if labels.wrappedValue.showsDates {
                    dateLabels(scale: scale, width: width, today: today, fits: fits, isClear: isClear)
                } else {
                    dayLabels(scale: scale, width: width, fits: fits, isClear: isClear)
                }
                if let today {
                    Text(todayLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .fixedSize()
                        .help(Text(now, format: dayFormat))
                        .offset(x: today.lowerBound)
                        .accessibilityHidden(true)
                }
                if let way, let goToToday {
                    TodayButton(label: todayLabel, isLater: way == .later, action: goToToday)
                        .frame(width: width, alignment: way == .later ? .trailing : .leading)
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(height: Self.height(for: labels.wrappedValue))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { goToToday?() }
        .contextMenu {
            Section {
                Toggle(isOn: labels.shows(dates: true)) { Text("Dates", bundle: .module) }
                    .disabled(labels.wrappedValue == .dates)
                Toggle(isOn: labels.shows(dates: false)) { Text("Days from Today", bundle: .module) }
                    .disabled(labels.wrappedValue == .days)
            } header: {
                Text("Label the Axis With", bundle: .module)
            }
        }
    }

    /// As tall as its labels: a line, or two with both the dates and the days.
    public static func height(for labels: AppSettings.AxisLabels) -> CGFloat {
        labels == .both ? 26 : Theme.axisHeaderHeight
    }

    /// The months or quarters, the weeks or days between them, and the month at the left where
    /// none is named; each but the last with its days from today under it, when they are shown too.
    @ViewBuilder
    private func dateLabels(
        scale: TickScale, width: CGFloat, today: ClosedRange<CGFloat>?, fits: @escaping (CGFloat) -> Bool,
        isClear: @escaping (ClosedRange<CGFloat>) -> Bool
    ) -> some View {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let counts = labels.wrappedValue.showsDays
        let majors = axis.ticks(scale.major, calendar: calendar).map { (date: $0, x: axis.x($0, width: width)) }
        let named = majors.map(\.x).filter(fits)
        let pinned = pinnedLabel(
            width: width, scale: scale, majors: majors.map(\.x), today: today, fits: fits, base: base)
        // Clear of the month labels, which take a little more room, and of the one at the left.
        let isFree = { (span: ClosedRange<CGFloat>) in
            named.allSatisfy { span.upperBound <= $0 - 1 || span.lowerBound >= $0 + 35 }
                && (pinned.map { span.upperBound <= $0.x || span.lowerBound >= $0.x + $0.room + 4 } ?? true)
        }
        if scale.labelledMinor == .day {
            let withWeekday = scale.dayWidth >= widestName(base.weekday(.abbreviated).day()) + 12
            ForEach(axis.dayIntervals(calendar: calendar), id: \.start) { day in
                let name =
                    withWeekday
                    ? day.start.formatted(base.weekday(.abbreviated).day())
                    : calendar.component(.day, from: day.start).formatted(.number.locale(locale))
                dayName(name, day: day, width: width, counts: counts, isShown: { isClear($0) && isFree($0) }) {
                    Text(verbatim: "\(day.start.formatted(dayFormat)) · \(daysFromToday(day.start))")
                }
            }
            .accessibilityHidden(true)
        } else if scale.labelledMinor == .week {
            ForEach(axis.ticks(.week, calendar: calendar), id: \.self) { date in
                let x = axis.x(date, width: width)
                let span = x + 3...x + 3 + max(17, dayCountWidth(of: date, counts))
                if fits(x), isFree(span), span.upperBound <= width {
                    // Just the number, quieter than a month in every language.
                    counted(date, counts) {
                        Text(calendar.component(.day, from: date), format: .number.locale(locale))
                            .foregroundStyle(.tertiary)
                    }
                    .help(Text(verbatim: "\(date.formatted(dayFormat)) · \(daysFromToday(date))"))
                    .offset(x: x + 3)
                }
            }
            .accessibilityHidden(true)
        }
        ForEach(majors, id: \.date) { tick in
            if fits(tick.x), tick.x + 3 + dayCountWidth(of: tick.date, counts) <= width {
                counted(tick.date, counts) {
                    Group {
                        if scale.major == .quarter, calendar.component(.month, from: tick.date) == 1 {
                            Text(tick.date, format: base.year())
                        } else {
                            Text(tick.date, format: base.month(.abbreviated))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .offset(x: tick.x + 3)
            }
        }
        .accessibilityHidden(true)
        if let pinned {
            pinned.label
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .offset(x: pinned.x + 3)
                .accessibilityHidden(true)
        }
    }

    /// The days from today: over the middle of each day where every day has room for one, otherwise
    /// every week or few weeks, as there is room, every fourth week, or every label when they are
    /// further apart, a little less quiet.
    @ViewBuilder
    private func dayLabels(
        scale: TickScale, width: CGFloat, fits: @escaping (CGFloat) -> Bool,
        isClear: @escaping (ClosedRange<CGFloat>) -> Bool
    ) -> some View {
        let today = Day(now, calendar: calendar)
        let step = scale.dayStep
        if step == 1 {
            ForEach(axis.dayIntervals(calendar: calendar), id: \.start) { day in
                let days = today.days(to: Day(day.start, calendar: calendar), calendar: calendar)
                if days != 0 {
                    dayName(RelativeDayText.label(days), day: day, width: width, isShown: isClear) {
                        Text(day.start, format: dayFormat)
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            let ticks = axis.ticks(every: step, from: today.startDate(calendar: calendar), calendar: calendar)
            ForEach(ticks, id: \.self) { date in
                let days = today.days(to: Day(date, calendar: calendar), calendar: calendar)
                let x = axis.x(date, width: width)
                if days != 0, fits(x) {
                    Text(RelativeDayText.label(days))
                        .font(.caption2)
                        .foregroundStyle(days % max(step, 28) == 0 ? .secondary : .tertiary)
                        .fixedSize()
                        .help(Text(date, format: dayFormat))
                        .offset(x: x + 3)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// A day's name over its middle, where its milestones stand, while `isShown` lets the room it
    /// takes be used, with its days from today under it where they `counts`; its date on hover,
    /// all across the day.
    @ViewBuilder
    private func dayName(
        _ name: String, day: DateInterval, width: CGFloat, counts: Bool = false,
        isShown: (ClosedRange<CGFloat>) -> Bool, help: () -> Text
    ) -> some View {
        let x0 = axis.x(day.start, width: width)
        let x1 = axis.x(day.end, width: width)
        let size = max(CGFloat(TextWidth.of(name, style: .caption2)), dayCountWidth(of: day.start, counts))
        if isShown((x0 + x1 - size) / 2...(x0 + x1 + size) / 2) {
            counted(day.start, counts, alignment: .center) {
                Text(verbatim: name)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: max(x1 - x0, size), alignment: .top)
            .contentShape(Rectangle())
            .help(help())
            .offset(x: (x0 + x1) / 2 - max(x1 - x0, size) / 2)
        }
    }

    /// A date's label, with how many days it is from today under it where it `counts` them.
    private func counted(
        _ date: Date, _ counts: Bool, alignment: HorizontalAlignment = .leading, label: () -> some View
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            label()
            if counts {
                Text(verbatim: dayCount(date))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .fixedSize()
    }

    /// "+12", how many days `date` is from today, as a date's label has it under it.
    private func dayCount(_ date: Date) -> String {
        RelativeDayText.label(Day(now, calendar: calendar).days(to: Day(date, calendar: calendar), calendar: calendar))
    }

    /// How wide the days from today under the label of `date` are, where it `counts` them.
    private func dayCountWidth(of date: Date, _ counts: Bool) -> CGFloat {
        counts ? CGFloat(TextWidth.of(dayCount(date), style: .caption2)) : 0
    }

    /// How wide the days from today under a date can be on this axis, as many digits as the
    /// farthest day has, so that the dates between the months leave room for them.
    private var widestDayCount: CGFloat {
        let today = Day(now, calendar: calendar)
        let ends = [axis.start, axis.end].map { today.days(to: Day($0, calendar: calendar), calendar: calendar) }
        let digits = String(ends.map(abs).max() ?? 0).count
        return CGFloat(TextWidth.of("−" + String(repeating: "0", count: digits), style: .caption2))
    }

    /// How wide the widest day name is in `format`, so that whether names carry their weekday
    /// depends only on how wide days are, and never changes while the axis moves.
    private func widestName(_ format: Date.FormatStyle) -> CGFloat {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 1, day: 19)) ?? now
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            return CGFloat(TextWidth.of(date.formatted(format), style: .caption2))
        }.max() ?? 0
    }

    /// "Mon, 20 Oct", for the label of a day.
    private var dayFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
    }

    /// "in 7 days", for a date label, which says how far away its day is on hover as a day label
    /// says its date.
    private func daysFromToday(_ date: Date) -> String {
        CardText.relative(Day(now, calendar: calendar).days(to: Day(date, calendar: calendar), calendar: calendar))
    }

    /// Where "Today" is written: just after the today line, or, where each day is named, over the
    /// middle of today in its place. `nil` when the axis is moved away from it.
    private func todaySpan(width: CGFloat, scale: TickScale) -> ClosedRange<CGFloat>? {
        guard axis.contains(now) else { return nil }
        let size = CGFloat(TextWidth.of(todayLabel, style: .caption2, weight: .semibold))
        let line = axis.x(now, width: width)
        let namesEachDay = labels.wrappedValue == .days ? scale.dayStep == 1 : scale.labelledMinor == .day
        guard namesEachDay else { return line + 3...line + 3 + size }
        let today = Day(now, calendar: calendar)
        let middle =
            (axis.x(today.startDate(calendar: calendar), width: width)
                + axis.x(today.endDate(calendar: calendar), width: width)) / 2
        let lead = min(max(middle - size / 2, 0), width - size)
        return lead...lead + size
    }

    /// The month, or far out the year, that the left of the axis is in, where nothing else says
    /// when that is: at the edge, after the way back to today, or after "Today" itself. `room`
    /// is about as wide as the label, for the labels around it to keep clear of.
    private func pinnedLabel(
        width: CGFloat, scale: TickScale, majors: [CGFloat], today: ClosedRange<CGFloat>?, fits: (CGFloat) -> Bool,
        base: Date.FormatStyle
    ) -> (x: CGFloat, room: CGFloat, label: Text)? {
        // A month that begins by "Today", hidden by it, is named after it, where its days are.
        let beginsByToday =
            today.map { today in
                majors.contains { $0 > today.lowerBound - Self.beforeToday && $0 < today.upperBound + Self.afterToday }
            } ?? false
        guard today == nil || beginsByToday || !majors.contains(where: fits) else { return nil }
        let x: CGFloat =
            switch (wayToToday, today) {
            case (.earlier, _): Self.earlierWayRoom + 4
            case (.later, _): 0
            case let (nil, today?): today.lowerBound >= 43 && !beginsByToday ? 0 : today.upperBound + 7
            case (nil, nil): 0
            }
        let date = axis.date(atX: x, width: width)
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let (label, room): (Text, CGFloat) =
            if scale.major == .quarter {
                (Text(date, format: base.year()), 40)
            } else if isThisYear {
                (Text(date, format: base.month(.abbreviated)), 36)
            } else {
                (Text(date, format: base.month(.abbreviated).year()), 64)
            }
        let isClear =
            !majors.contains { $0 > x - 4 && $0 < x + room }
            && (today.map { x >= $0.upperBound + 4 || $0.lowerBound - x >= room } ?? true)
            && x + room < width - (wayToToday == .later ? Self.laterWayRoom : Self.edgeRoom)
        return isClear ? (x, room, label) : nil
    }

    private enum Way { case earlier, later }

    /// The room labels keep clear for the way back to today, at the left end or the right one, and
    /// at the right edge.
    private static let earlierWayRoom: CGFloat = 56
    private static let laterWayRoom: CGFloat = 64
    private static let edgeRoom: CGFloat = 24
    /// The room labels keep clear before and after "Today".
    private static let beforeToday: CGFloat = 41
    private static let afterToday: CGFloat = 5

    /// Where today is, when it is off the axis.
    private var wayToToday: Way? {
        if now < axis.start { return .earlier }
        if now > axis.end { return .later }
        return nil
    }
}

/// "‹ Today" or "Today ›" at the edge of a moved axis.
private struct TodayButton: View {
    let label: String
    let isLater: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if !isLater {
                    Image(systemName: "chevron.left")
                }
                Text(label)
                if isLater {
                    Image(systemName: "chevron.right")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Back to Today", bundle: .module))
        .accessibilityLabel(Text("Back to Today", bundle: .module))
    }
}

/// The background of each row's bar area: very light lines between the days where days are wide
/// enough, at the weeks and at the months (at the quarters when zoomed far out), the weekends
/// lightly shaded, and the "today" line. Labelled with the days from today, the weeks and the
/// stronger lines count from today instead. Every row draws its own piece; with no row spacing they
/// join into continuous lines. It glides with the bars when the axis moves.
public struct AxisGrid: View {
    public var axis: TimeAxis
    public let now: Date
    @Environment(\.axisLabels) private var labels
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    private let calendar = Calendar.gregorianLocal

    public init(axis: TimeAxis, now: Date) {
        self.axis = axis
        self.now = now
    }

    public var body: some View {
        let ink = contrast == .increased ? 2.0 : 1
        let pixel = 1 / displayScale
        Canvas { context, size in
            let scale = TickScale(axis: axis, width: size.width)
            // On the pixel grid, in the gap where the blocks of two days meet.
            func x(_ date: Date) -> CGFloat {
                ((axis.x(date, width: size.width) - Theme.blockGap / 2) / pixel).rounded() * pixel
            }
            func band(_ x0: CGFloat, _ x1: CGFloat, _ opacity: Double) {
                guard x1 > x0 else { return }
                context.fill(
                    Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                    with: .color(.primary.opacity(opacity * ink)))
            }
            if scale.weekends > 0 {
                for weekend in axis.weekends(calendar: calendar) {
                    band(x(weekend.start), x(weekend.end), 0.035 * scale.weekends)
                }
            }
            for (date, opacity) in lines(scale) {
                band(x(date), x(date) + pixel, opacity)
            }
            if axis.contains(now) {
                let line = axis.x(now, width: size.width)
                context.fill(Path(CGRect(x: line - 0.75, y: 0, width: 1.5, height: size.height)), with: .style(.tint))
            }
        }
        .accessibilityHidden(true)
    }

    /// Each line once, as strong as the most it stands for: a day, a week, a month or a quarter.
    private func lines(_ scale: TickScale) -> [Date: Double] {
        var lines: [Date: Double] = [:]
        func add(_ dates: [Date], _ opacity: Double) {
            for date in dates {
                lines[date] = max(lines[date] ?? 0, opacity)
            }
        }
        let day = 0.05 * scale.dayLines
        if day > 0 {
            add(axis.ticks(.day, calendar: calendar), day)
        }
        if labels.wrappedValue == .days {
            let today = calendar.startOfDay(for: now)
            if scale.showsWeekLines {
                add(axis.ticks(every: 7, from: today, calendar: calendar), max(0.035, day))
            }
            add(axis.ticks(every: max(scale.dayStep, 28), from: today, calendar: calendar), 0.07)
        } else {
            if scale.showsWeekLines {
                add(axis.ticks(.week, calendar: calendar), max(0.035, day))
            }
            add(axis.ticks(.month, calendar: calendar), scale.major == .month ? 0.07 : 0.035)
            if scale.major == .quarter {
                add(axis.ticks(.quarter, calendar: calendar), 0.07)
            }
        }
        return lines
    }
}

extension AxisHeader: Animatable {
    /// The labels move with the axis frame by frame, as the grid does, and come in at the edges.
    public nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }
}

extension AxisGrid: Animatable {
    public nonisolated var animatableData: AxisMotion {
        get { axis.animatableData(around: now) }
        set { axis.setAnimatableData(newValue, around: now) }
    }
}

/// How finely an axis is divided, from how wide its days are drawn.
struct TickScale {
    let dayWidth: CGFloat
    /// How wide the days from today under the dates can be, where both are shown.
    let dayCountWidth: CGFloat

    init(axis: TimeAxis, width: CGFloat, dayCountWidth: CGFloat = 0) {
        dayWidth = axis.dayWidth(in: width)
        self.dayCountWidth = dayCountWidth
    }

    /// Months get labels while they have room for one; past that, quarters do.
    var major: TimeAxis.Unit {
        dayWidth * 30 >= 30 ? .month : .quarter
    }

    /// Every day where days have room for a number, otherwise the first day of each week where
    /// weeks have room, also for the days from today under them where those are shown.
    var labelledMinor: TimeAxis.Unit? {
        dayWidth >= max(20, dayCountWidth + 4) ? .day : dayWidth * 7 >= max(26, dayCountWidth + 4) ? .week : nil
    }

    /// Labelled with the days from today: every day where a day has room for "+12", otherwise
    /// every week, or every so many weeks, the fewest that leave room. Every label then falls on
    /// the same day of the week as today.
    var dayStep: Int {
        guard dayWidth < 24 else { return 1 }
        return [7, 14, 28, 56, 91, 182].first { CGFloat($0) * dayWidth >= 30 } ?? 364
    }

    /// How strongly the lines between days and the weekends are drawn, from nothing to full as
    /// days widen, so that they come in gradually while zooming: the lines from 8 to 20 pt a day,
    /// where each day gets its name; the weekends from 6 to 10.
    var dayLines: Double { ramp(from: 8, to: 20) }
    var weekends: Double { ramp(from: 6, to: 10) }
    var showsWeekLines: Bool { dayWidth * 7 >= 10 }

    private func ramp(from low: CGFloat, to high: CGFloat) -> Double {
        Double(min(max((dayWidth - low) / (high - low), 0), 1))
    }
}
