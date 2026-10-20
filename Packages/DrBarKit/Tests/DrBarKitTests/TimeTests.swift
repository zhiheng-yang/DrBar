import Foundation
import Testing

@testable import DrBarKit

let amsterdam = Calendar.gregorian(in: TimeZone(identifier: "Europe/Amsterdam")!)

func date(_ text: String, _ zone: TimeZone = .gmt) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

@Suite struct DayTests {
    @Test func dayDependsOnTheTimeZone() {
        let instant = date("2026-11-17 11:59")  // CVPR 2027 in AoE
        #expect(Day(instant, calendar: amsterdam) == Day(year: 2026, month: 11, day: 17))
        #expect(
            Day(instant, calendar: .gregorian(in: DeadlineTimeZone.anywhereOnEarth))
                == Day(year: 2026, month: 11, day: 16))
    }

    @Test func arithmeticAcrossDaylightSaving() {
        // Europe switches back to winter time on 25 October 2026.
        let before = Day(year: 2026, month: 10, day: 24)
        #expect(before.adding(2, calendar: amsterdam) == Day(year: 2026, month: 10, day: 26))
        #expect(before.days(to: Day(year: 2026, month: 10, day: 26), calendar: amsterdam) == 2)
        #expect(
            Day(year: 2026, month: 3, day: 1).days(to: Day(year: 2026, month: 2, day: 27), calendar: amsterdam) == -2)
        let start = Day(year: 2026, month: 10, day: 25).startDate(calendar: amsterdam)
        let end = Day(year: 2026, month: 10, day: 25).endDate(calendar: amsterdam)
        #expect(end.timeIntervalSince(start) == 25 * 3600)
    }

    @Test func codesAsISODate() throws {
        let day = Day(year: 2026, month: 3, day: 5)
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-03-05\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [day])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Day].self, from: Data("[\"5 March\"]".utf8)) }
    }

    @Test(arguments: ["2026-13-01", "2026-00-10", "2026-1", "", "x-y-z"])
    func rejectsMalformedText(_ text: String) {
        #expect(Day(string: text) == nil)
    }

    @Test func ordering() {
        #expect(Day(year: 2026, month: 12, day: 31) < Day(year: 2027, month: 1, day: 1))
        #expect(Day(year: 2026, month: 2, day: 1) > Day(year: 2026, month: 1, day: 31))
    }
}

@Suite struct DeadlineTimeZoneTests {
    @Test(arguments: [
        ("AoE", -12 * 3600), ("aoe", -12 * 3600), ("UTC", 0), ("UTC+0", 0), ("GMT", 0),
        ("UTC-12", -12 * 3600), ("UTC+8", 8 * 3600), ("UTC+5:30", 5 * 3600 + 1800), (" UTC-7 ", -7 * 3600),
    ])
    func fixedOffsets(_ raw: String, _ seconds: Int) throws {
        let zone = try #require(DeadlineTimeZone.ccf(raw))
        #expect(zone.secondsFromGMT(for: date("2026-01-01 00:00")) == seconds)
    }

    @Test func pacificTimeObservesDaylightSaving() throws {
        let zone = try #require(DeadlineTimeZone.ccf("PT"))
        #expect(zone.secondsFromGMT(for: date("2026-07-01 00:00")) == -7 * 3600)
        #expect(zone.secondsFromGMT(for: date("2026-12-01 00:00")) == -8 * 3600)
    }

    @Test(arguments: ["CET", "PST", "UTC+15", "UTC+5:75", "Europe/Amsterdam", "", "UTC++1"])
    func otherNotationsAreNotRecognizedForCCF(_ raw: String) {
        #expect(DeadlineTimeZone.ccf(raw) == nil)
    }

    @Test func customDeadlinesAlsoAcceptIdentifiers() {
        #expect(DeadlineTimeZone.custom("Europe/Amsterdam")?.identifier == "Europe/Amsterdam")
        #expect(DeadlineTimeZone.custom("AoE") != nil)
        #expect(DeadlineTimeZone.customChoices.first == "AoE")
        #expect(DeadlineTimeZone.customChoices.contains("UTC+14"))
        #expect(!DeadlineTimeZone.customChoices.contains("UTC+0"))
        #expect(DeadlineTimeZone.customChoices.allSatisfy { DeadlineTimeZone.ccf($0) != nil })
    }
}

@Suite struct TimeAxisTests {
    let now = date("2026-10-12 14:00", TimeZone(identifier: "Europe/Amsterdam")!)

    @Test func runsFromAWeekAgoToTheChosenMonths() {
        let axis = TimeAxis(now: now, range: .threeMonths, calendar: amsterdam)
        #expect(axis.start == date("2026-10-05 00:00", amsterdam.timeZone))
        #expect(axis.end == date("2027-01-12 00:00", amsterdam.timeZone))
    }

    @Test(arguments: [(AxisRange.month, "2026-10-10 00:00"), (.sixMonths, "2026-09-28 00:00")])
    func looksBackBriefly(range: AxisRange, start: String) {
        let axis = TimeAxis(now: now, range: range, calendar: amsterdam)
        #expect(axis.start == date(start, amsterdam.timeZone))
        #expect((0.06...0.1).contains(axis.fraction(now)))
    }

    @Test func aWeekLooksBackADay() {
        let axis = TimeAxis(now: now, range: .week, calendar: amsterdam)
        #expect(axis.start == date("2026-10-11 00:00", amsterdam.timeZone))
        #expect(axis.end == date("2026-10-19 00:00", amsterdam.timeZone))
        #expect(axis.days == 8)
    }

    @Test func everyDayOnTheAxisWholeOrInPart() {
        let week = TimeAxis(now: now, range: .week, calendar: amsterdam)
        #expect(week.dayIntervals(calendar: amsterdam).count == 8)
        let shifted = TimeAxis(now: now, range: .week, shiftedBy: 0.5, calendar: amsterdam)
        #expect(shifted.dayIntervals(calendar: amsterdam).count == 9)
        // The day the clocks go back is 25 hours long.
        let autumn = TimeAxis(now: date("2026-10-24 12:00", amsterdam.timeZone), range: .week, calendar: amsterdam)
        let sunday = autumn.dayIntervals(calendar: amsterdam).first {
            Day($0.start, calendar: amsterdam) == Day(year: 2026, month: 10, day: 25)
        }
        #expect(sunday.map { abs($0.duration - 25 * 3600) < 1 } == true)
    }

    @Test func weekendsAsTheRegionKeepsThem() throws {
        var british = Calendar.gregorian(in: amsterdam.timeZone)
        british.locale = Locale(identifier: "en_GB")
        let axis = TimeAxis(now: now, range: .month, calendar: british)
        let weekends = axis.weekends(calendar: british)
        let first = try #require(weekends.first)
        #expect(british.component(.weekday, from: first.start) == 7)
        // One that the axis starts in is there too: on a Monday, it starts on Sunday.
        let monday = TimeAxis(now: date("2026-10-19 12:00", amsterdam.timeZone), range: .week, calendar: british)
        #expect(monday.weekends(calendar: british).first.map { $0.start < monday.start } == true)
        var israeli = Calendar.gregorian(in: amsterdam.timeZone)
        israeli.locale = Locale(identifier: "he_IL")
        let friday = try #require(axis.weekends(calendar: israeli).first)
        #expect(israeli.component(.weekday, from: friday.start) == 6)
    }

    @Test func positionsAreProportionalAndClamped() {
        let axis = TimeAxis(now: now, range: .month, calendar: amsterdam)
        #expect(axis.x(axis.start, width: 300) == 0)
        #expect(axis.x(axis.end, width: 300) == 300)
        #expect(axis.x(axis.end.addingTimeInterval(86_400 * 30), width: 300) == 300)
        #expect(axis.x(axis.start.addingTimeInterval(-86_400), width: 300) == 0)
        let middle = axis.start.addingTimeInterval(axis.end.timeIntervalSince(axis.start) / 2)
        #expect(abs(axis.x(middle, width: 300) - 150) < 0.001)
        #expect(axis.contains(now))
    }

    @Test func shiftedAxisKeepsItsSpan() {
        let axis = TimeAxis(now: now, range: .threeMonths, calendar: amsterdam)
        let earlier = TimeAxis(now: now, range: .threeMonths, shiftedBy: -30.5, calendar: amsterdam)
        #expect(earlier.start == axis.start.addingTimeInterval(-30.5 * 86_400))
        #expect(earlier.end == axis.end.addingTimeInterval(-30.5 * 86_400))
        #expect(!TimeAxis(now: now, range: .month, shiftedBy: 60, calendar: amsterdam).contains(now))
        #expect(abs(axis.dayWidth(in: 400) * CGFloat(axis.days) - 400) < 0.001)
    }

    @Test func positionsTurnBackIntoDates() {
        let axis = TimeAxis(now: now, range: .threeMonths, calendar: amsterdam)
        let moment = date("2026-11-03 06:00", amsterdam.timeZone)
        #expect(abs(axis.date(atX: axis.x(moment, width: 640), width: 640).timeIntervalSince(moment)) < 1)
        #expect(axis.date(atX: 0, width: 640) == axis.start)
    }

    @Test func zoomingKeepsTodayInItsPlace() {
        let axis = TimeAxis(now: now, range: .threeMonths, calendar: amsterdam)
        let closer = TimeAxis(now: now, range: .threeMonths, zoom: 2, calendar: amsterdam)
        #expect(abs(closer.days - axis.days / 2) < 0.001)
        #expect(
            abs(closer.fraction(amsterdam.startOfDay(for: now)) - axis.fraction(amsterdam.startOfDay(for: now))) < 1e-9)
        #expect(closer.lookBack == axis.lookBack / 2)
    }

    @Test func ticksEveryFewDaysFromToday() {
        let calendar = Calendar.gregorian(in: TimeZone(identifier: "Europe/Amsterdam")!)
        let axis = TimeAxis(now: now, range: .threeMonths, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let weeks = axis.ticks(every: 7, from: today, calendar: calendar)
        #expect(weeks.first == today)
        #expect(weeks.count == 14)
        // Across the end of summer time, still at midnight.
        #expect(weeks.allSatisfy { calendar.startOfDay(for: $0) == $0 })
        #expect(zip(weeks, weeks.dropFirst()).allSatisfy { calendar.dateComponents([.day], from: $0, to: $1).day == 7 })
        let back = TimeAxis(now: now, range: .threeMonths, shiftedBy: -30, calendar: calendar)
        let days = back.ticks(every: 1, from: today, calendar: calendar)
        #expect(days.contains(calendar.date(byAdding: .day, value: -20, to: today)!))
        #expect(axis.ticks(every: 0, from: today, calendar: calendar).isEmpty)
    }

    @Test func ticksOfEachUnit() {
        var calendar = amsterdam
        calendar.firstWeekday = 2  // Monday
        let axis = TimeAxis(now: now, range: .threeMonths, calendar: calendar)
        let months = axis.ticks(.month, calendar: calendar).map { Day($0, calendar: calendar) }
        #expect(
            months == [
                Day(year: 2026, month: 11, day: 1), Day(year: 2026, month: 12, day: 1),
                Day(year: 2027, month: 1, day: 1),
            ])
        let weeks = axis.ticks(.week, calendar: calendar)
        #expect(weeks.allSatisfy { calendar.component(.weekday, from: $0) == 2 })
        #expect(Day(weeks[0], calendar: calendar) == Day(year: 2026, month: 10, day: 12))
        let days = TimeAxis(now: now, range: .month, calendar: calendar).ticks(.day, calendar: calendar)
        #expect(days.count == 33)
        #expect(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        let quarters = TimeAxis(now: now, range: .sixMonths, zoom: 0.4, calendar: calendar).ticks(
            .quarter, calendar: calendar)
        #expect(quarters.map { calendar.component(.month, from: $0) } == [10, 1, 4, 7, 10, 1])
        #expect(quarters.allSatisfy { calendar.component(.day, from: $0) == 1 })
    }
}

@Suite struct AxisPositionTests {
    let now = date("2026-10-12 14:00", TimeZone(identifier: "Europe/Amsterdam")!)

    @Test func panningFollowsTheFingers() {
        var position = AxisPosition()
        let dayWidth = position.axis(now: now, range: .threeMonths).dayWidth(in: 400)
        position.pan(by: dayWidth * 10, width: 400, now: now, range: .threeMonths)
        #expect(abs(position.shift + 10) < 1e-9)
        position.pan(by: -100_000, width: 400, now: now, range: .threeMonths)
        #expect(position.shift == AxisPosition.shiftLimit)
    }

    @Test func zoomingKeepsTheMomentUnderTheFingers() {
        var position = AxisPosition(shift: -20)
        let before = position.axis(now: now, range: .threeMonths)
        let moment = before.start.addingTimeInterval(0.3 * before.end.timeIntervalSince(before.start))
        position.zoom(by: 2.5, at: 0.3, now: now, range: .threeMonths)
        let after = position.axis(now: now, range: .threeMonths)
        #expect(abs(after.fraction(moment) - 0.3) < 1e-9)
        #expect(abs(after.days - before.days / 2.5) < 1e-6)
    }

    @Test func zoomStaysBetweenTenDaysAndTwoYears() {
        var position = AxisPosition()
        position.zoom(by: 1000, at: 0.5, now: now, range: .threeMonths)
        #expect(abs(position.axis(now: now, range: .threeMonths).days - TimeAxis.visibleDays.lowerBound) < 1e-6)
        position.zoom(by: 0.0001, at: 0.5, now: now, range: .threeMonths)
        #expect(abs(position.axis(now: now, range: .threeMonths).days - TimeAxis.visibleDays.upperBound) < 1e-6)
    }

    @Test func zoomingOutNeverLeavesTodayBehind() {
        for fraction in [0.0, 0.1, 0.5, 0.9, 1.0] {
            for points in [-100_000.0, 100_000.0] {
                var position = AxisPosition()
                position.pan(by: points, width: 400, now: now, range: .threeMonths)
                position.zoom(by: 0.0001, at: fraction, now: now, range: .threeMonths)
                let axis = position.axis(now: now, range: .threeMonths)
                #expect(axis.contains(now))
                #expect(abs(axis.days - TimeAxis.visibleDays.upperBound) < 1e-6)
            }
        }
    }

    /// A pinch squeezed shut reports no size at all, which once turned the axis into nothing.
    @Test func zoomingByNoSizeChangesNothing() {
        var position = AxisPosition(zoom: 2, shift: 5)
        for factor in [0, -1, .nan, .infinity] {
            position.zoom(by: factor, at: 0.5, now: now, range: .threeMonths)
        }
        #expect(position == AxisPosition(zoom: 2, shift: 5))
        position.pan(by: .nan, width: 400, now: now, range: .threeMonths)
        position.pan(by: 10, width: 0, now: now, range: .threeMonths)
        #expect(position == AxisPosition(zoom: 2, shift: 5))
        position.zoom(by: 0.5, at: .nan, now: now, range: .threeMonths)
        #expect(position.zoom == 1)
        #expect(position.shift.isFinite)
    }

    @Test func pinchingOutForLongStillShowsToday() {
        var position = AxisPosition()
        for _ in 0..<500 {
            position.zoom(by: 0.95, at: 0.8, now: now, range: .threeMonths)
        }
        let axis = position.axis(now: now, range: .threeMonths)
        #expect(axis.contains(now))
        #expect(abs(axis.days - TimeAxis.visibleDays.upperBound) < 1e-6)
    }

    @Test func aPinchStopsAtTheChosenRangeThenGoesOn() {
        var position = AxisPosition(zoom: 0.8)
        var detent = ZoomDetent()
        var stops = 0
        // Pinching open by 5 % at a time: the fourth step comes near enough to stop, the fifth is held.
        for _ in 0..<5 {
            if position.pinch(by: 1.05, at: 0.5, detent: &detent, now: now, range: .threeMonths) {
                stops += 1
            }
        }
        #expect(position.zoom == 1)
        #expect(stops == 1)
        position.pinch(by: 1.05, at: 0.5, detent: &detent, now: now, range: .threeMonths)
        #expect(position.zoom == 1)
        // Past the hold, it goes on by only what is beyond it, without a jump.
        position.pinch(by: 1.05, at: 0.5, detent: &detent, now: now, range: .threeMonths)
        #expect(position.zoom > 1 && position.zoom < 1.05)
    }

    @Test func aPinchStartingAtTheChosenRangeOrLeavingItIsNotHeld() {
        var position = AxisPosition()
        var detent = ZoomDetent()
        position.pinch(by: 1.05, at: 0.5, detent: &detent, now: now, range: .threeMonths)
        #expect(abs(position.zoom - 1.05) < 1e-9)
        position.pinch(by: 1.02, at: 0.5, detent: &detent, now: now, range: .threeMonths)
        #expect(abs(position.zoom - 1.071) < 1e-9)
        // Through it at once, from the other side, it still stops.
        position.pinch(by: 0.8, at: 0.5, detent: &detent, now: now, range: .threeMonths)
        #expect(position.zoom == 1)
    }

    @Test(arguments: AxisRange.allCases)
    func actualSizeIsExactlyTheChosenRange(range: AxisRange) {
        var position = AxisPosition()
        for _ in 0..<3 {
            position.zoom(by: 1.5, now: now, range: range)
        }
        position.zoom(to: 1, now: now, range: range)
        #expect(position.zoom == 1)
    }

    @Test func stepsGrowWithWhatIsOnScreen() {
        var position = AxisPosition()
        position.step(1, now: now, range: .week)
        #expect(position.shift == 7)
        position = AxisPosition(zoom: 2)
        position.step(1, now: now, range: .week)
        #expect(position.shift == 1)
        position = AxisPosition()
        position.step(1, now: now, range: .month)
        #expect(position.shift == 7)
        position = AxisPosition()
        position.step(-1, now: now, range: .threeMonths)
        #expect(position.shift == -30)
        position = AxisPosition(zoom: 0.3)
        position.step(1, now: now, range: .threeMonths)
        #expect(position.shift == 91)
    }
}

@Suite struct MeetingDatesTests {
    @Test(arguments: [
        ("June 20-25, 2027", "2027-06-20", "2027-06-25"),
        ("June 30 - July 3, 2026", "2026-06-30", "2026-07-03"),
        ("July 3 - 4, 2026", "2026-07-03", "2026-07-04"),
        ("February 27-March 2, 2025", "2025-02-27", "2025-03-02"),
        ("March 31- April 2, 2025", "2025-03-31", "2025-04-02"),
        ("April 29, 2025", "2025-04-29", "2025-04-29"),
        ("FEBRUARY 25-27, 2025", "2025-02-25", "2025-02-27"),
        ("November 22-26 2026", "2026-11-22", "2026-11-26"),
        ("Sept 8-10, 2026", "2026-09-08", "2026-09-10"),
        ("Dec. 3-5, 2026", "2026-12-03", "2026-12-05"),
    ])
    func readsTheUsualForms(_ text: String, _ start: String, _ end: String) throws {
        let meeting = try #require(MeetingDates(parsing: text))
        #expect(meeting.start == Day(string: start))
        #expect(meeting.end == Day(string: end))
    }

    @Test(arguments: [
        "TBD", "May 2027 (exact dates TBD)", "June 22 and June 24-26, 2025", "Dec, 2025",
        "December 6-9, 2027 (To be confirmed)", "February 30-31, 2027", "June 25-20, 2027", "Juneteenth 3, 2026",
    ])
    func leavesEverythingElseAlone(_ text: String) {
        #expect(MeetingDates(parsing: text) == nil)
    }

    @Test func shortPlace() {
        func place(_ text: String?) -> String? {
            ConferenceEdition(
                id: "x", year: 2027, link: "", timeZone: "AoE", date: nil, place: text, rounds: [], previous: nil
            )
            .shortPlace
        }
        #expect(place("Seattle, WA, United States") == "Seattle")
        #expect(place("Vienna, Austria (Hybrid)") == "Vienna")
        #expect(place("Kyoto (hybrid), Japan") == "Kyoto")
        #expect(place("Paris (France, online too)") == "Paris")
        #expect(place("PHILADELPHIA, PENNSYLVANIA, USA") == "Philadelphia")
        #expect(place("Singapore EXPO") == "Singapore EXPO")
        #expect(place("TBD") == nil)
        #expect(place(nil) == nil)
    }
}

@Suite struct MailtoLinkTests {
    @Test func encodesSubjectAndBody() throws {
        let url = try #require(
            MailtoLink.url(
                to: ["jane.doe@example.org", " sam@example.org"], subject: "Re: Progress: A+B",
                body: "Hi!\nTarget: CVPR & ICCV"))
        #expect(
            url.absoluteString
                == "mailto:jane.doe@example.org,sam@example.org?subject=Re:%20Progress:%20A%2BB&body=Hi!%0D%0ATarget:%20CVPR%20%26%20ICCV"
        )
    }
}
