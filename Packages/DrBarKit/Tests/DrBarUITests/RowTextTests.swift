import DrBarKit
import Foundation
import SwiftUI
import Testing

@testable import DrBarUI

@Suite struct RowTextTests {
    let now = Date(timeIntervalSince1970: 1_791_806_400)

    @Test func theFlagOfAnUnnamedDeadlineIsNamedByItsDay() {
        let date = now.addingTimeInterval(17 * 86_400)
        var own = PaperDeadline(
            id: "own", source: .own(UUID()), value: DeadlineValue(raw: "", date: date), timeZone: "AoE")
        #expect(own.flagName == date.formatted(.dateTime.month(.abbreviated).day()))
        own.title = "Letters"
        #expect(own.flagName == "Letters")
        let paper = PaperDeadline(
            id: "cvpr27|paper|#1", source: .conference(.paper), value: DeadlineValue(raw: "", date: date),
            timeZone: "UTC-12")
        #expect(paper.flagName == paper.shortName)
    }

    @Test @MainActor func theFlagsOfAGroupsLineAreNamedForTheirWork() {
        let unnamed = CustomDeadline(title: "", date: now.addingTimeInterval(17 * 86_400))
        let letters = CustomDeadline(title: "Letters", date: now.addingTimeInterval(9 * 86_400))
        let jcc = Paper(title: "JCC", deadlines: [unnamed, letters], mainDeadline: unnamed.id, groupID: UUID())
        let new = Paper(title: "C1", groupID: jcc.groupID)
        let work = [jcc, new].map {
            DueWork(id: $0.id, title: $0.displayTitle, overview: PaperOverview(paper: $0, catalog: .empty, now: now))
        }
        let deadlines = DueLane<EmptyView>.deadlines(of: work, now: now)
        #expect(deadlines.map(\.style) == [.open, .flag, .undated])
        // On the shared line, each is told apart by its work, as two papers may aim at one date.
        #expect(deadlines.map(\.owner) == [jcc.id, jcc.id, new.id])
        #expect(deadlines[1].id == "\(jcc.id)|\(unnamed.id)")

        let lane = DeadlineTrack.Lane(
            titles: [jcc.id: "JCC", new.id: "C1"], open: { _ in }, menu: { _ in AnyView(EmptyView()) },
            card: { _ in nil })
        #expect(lane.label(of: [deadlines[1]]) == "JCC")
        #expect(lane.label(of: [deadlines[0]]) == "JCC · Letters")
        // A title stands once, however many of its deadlines the flag holds.
        #expect(lane.label(of: [deadlines[0], deadlines[1], deadlines[2]]) == "JCC · Letters · C1")
        #expect(lane.name(of: deadlines[0]) == "JCC · Letters")
        #expect(lane.name(of: deadlines[1]) == "JCC")
    }

    @Test @MainActor func noWorkOnALineGoesWithoutAMark() {
        let axis = TimeAxis(start: now, end: now.addingTimeInterval(30 * 86_400), lookBack: 86_400)
        let deadline = { (id: String, days: Double, style: TimelineDeadline.Style, owner: UUID) in
            let date = now.addingTimeInterval(days * 86_400)
            return TimelineDeadline(
                deadline: PaperDeadline(
                    id: id, source: .own(UUID()), value: DeadlineValue(raw: "", date: date), timeZone: "AoE"),
                date: date, style: style, label: id, owner: owner)
        }
        let (onAxis, ahead, done, undated) = (UUID(), UUID(), UUID(), UUID())
        let deadlines = [
            deadline("shown", 10, .flag, onAxis), deadline("later", 40, .open, onAxis),
            deadline("ahead", 45, .flag, ahead),
            deadline("first", -20, .closed, done), deadline("last", -5, .closed, done),
            TimelineDeadline(
                deadline: PaperDeadline(
                    id: "none", source: .own(undated), value: DeadlineValue(raw: "", date: nil), timeZone: ""),
                date: .distantFuture, style: .undated, label: "Draft", owner: undated),
        ]
        let beyond = DeadlineTrack.Lane.beyond(deadlines, axis: axis)
        // The red flag ahead, the latest of what is done, and the work with no date.
        #expect(beyond == ["\(ahead)|ahead", "\(done)|last", "\(undated)|none"])
    }

    @Test @MainActor func theRedOneStandsAsAFlagWhereThereIsRoom() {
        let axis = TimeAxis(start: now, end: now.addingTimeInterval(30 * 86_400), lookBack: 86_400)
        let date = now.addingTimeInterval(15 * 86_400)
        let red = TimelineDeadline(
            deadline: PaperDeadline(
                id: "paper", source: .conference(.paper), value: DeadlineValue(raw: "", date: date), timeZone: "AoE"),
            date: date, style: .flag, label: "Paper")
        func flag(room: CGFloat, diamonds: [Double] = []) -> DeadlineTicks.Flag? {
            DeadlineTicks.flag(
                [red], diamonds: diamonds.map { now.addingTimeInterval($0 * 86_400) }, axis: axis, width: 300,
                diamondSize: 9, room: room)
        }
        #expect(flag(room: 6) == nil)
        let standing = flag(room: 10)
        #expect(standing?.size == 9 && standing?.isMirrored == false)
        // On the bar just before the tick at 150, not on top of it as its pole.
        #expect(standing?.rect.maxY == 0 && standing?.rect.maxX == 147.5)
        // A diamond just before the deadline turns it round, after the tick; one on each side
        // leaves the tick alone.
        #expect(flag(room: 10, diamonds: [16])?.isMirrored == false)
        #expect(flag(room: 10, diamonds: [14])?.isMirrored == true)
        #expect(flag(room: 10, diamonds: [14, 16]) == nil)
    }

    @Test @MainActor func theLastLabelsOfTheAxisStayShown() {
        var labels = AppSettings.AxisLabels.dates
        let binding = Binding(get: { labels }, set: { labels = $0 })
        binding.shows(dates: false).wrappedValue = true
        #expect(labels == .both)
        binding.shows(dates: true).wrappedValue = false
        #expect(labels == .days)
        binding.shows(dates: false).wrappedValue = false
        #expect(labels == .days)
    }

    @Test @MainActor func thinBarsKeepTheirTracksApartByLess() {
        #expect(PlanBar.trackGap(height: 14, tracks: 2) == Theme.blockGap)
        #expect(PlanBar.trackGap(height: 14, tracks: 3) == 1)
        #expect(PlanBar.trackGap(height: 8, tracks: 4) == 0)
    }

    @Test func aPlaceHasTheFlagOfItsCountry() {
        #expect(MeetingText.place("Marrakesh, Morocco") == "Marrakesh, Morocco 🇲🇦")
        #expect(MeetingText.place("Columbia", flags: "🇺🇸") == "Columbia 🇺🇸")
        #expect(MeetingText.place("Virtual") == "Virtual")
    }

    @Test func aFlagsCardSaysWhatTheRowSaidUnderTheName() {
        let item = Paper(title: "Draft", groupID: UUID())
        let overview = PaperOverview(paper: item, catalog: .empty, now: now)
        #expect(HoverCard.paper(item, overview: overview, people: [:], now: now) == nil)
        let card = HoverCard.paper(item, overview: overview, people: [:], now: now, hasRow: false)
        #expect(card?.title == "Draft")
    }
}
