import DrBarKit
import Foundation
import Testing

@testable import DrBarUI

@Suite struct HoverCardTests {
    let now = Date(timeIntervalSince1970: 1_791_806_400)
    var today: Day { Day(now) }
    let jane = Person(name: "Jane Doe", email: "jane@example.com")
    let sam = Person(name: "Sam Lee", email: "sam@example.com")

    func lines(_ card: HoverCard?) -> [HoverCard.Line] {
        card?.sections.flatMap { section -> [HoverCard.Line] in
            if case let .lines(lines) = section { return lines }
            return []
        } ?? []
    }

    func dates(_ card: HoverCard?) -> [HoverCard.DateLine] {
        card?.sections.flatMap { section -> [HoverCard.DateLine] in
            if case let .dates(dates) = section { return dates }
            return []
        } ?? []
    }

    @Test func aBlockWhoseBarSaysItAllHasNone() {
        let block = TimeBlock(kind: .writing, start: today, end: today.adding(9))
        let card = HoverCard.block(
            block, name: "Writing", people: [], isNameShown: true, deadline: today.adding(20), now: now)
        #expect(card == nil)
    }

    @Test func aBlockSaysWhoWorksOnIt() {
        let block = TimeBlock(kind: .review, start: today, end: today.adding(6), people: [jane.id])
        let card = HoverCard.block(
            block, name: "Internal review", people: [jane], isNameShown: true, deadline: nil, now: now)
        #expect(card?.title == "Internal review")
        #expect(lines(card).first?.tone == .primary)
        #expect(lines(card).contains { $0.text.contains("Jane Doe") })
    }

    @Test func aBlockNamesItselfWhereItsBarCutsTheNameShort() {
        let block = TimeBlock(kind: .custom, customName: "Research proposal", start: today, end: today.adding(3))
        let card = HoverCard.block(
            block, name: "Research proposal", people: [], isNameShown: false, deadline: nil, now: now)
        #expect(card?.title == "Research proposal")
        #expect(lines(card).count == 1)
    }

    @Test func aBlockSaysWhyItIsMarked() {
        let late = TimeBlock(kind: .writing, start: today, end: today.adding(12))
        let past = HoverCard.block(
            late, name: "Writing", people: [], isNameShown: true, deadline: today.adding(9), now: now)
        #expect(lines(past).map(\.tone) == [.primary, .alert])
        let undone = TimeBlock(kind: .experiments, start: today.adding(-9), end: today.adding(-2))
        let behind = HoverCard.block(
            undone, name: "Experiments", people: [], isNameShown: true, deadline: nil, now: now)
        #expect(lines(behind).map(\.tone) == [.primary, .warning])
        var done = undone
        done.isDone = true
        #expect(
            HoverCard.block(done, name: "Experiments", people: [], isNameShown: true, deadline: nil, now: now) == nil)
    }

    @Test func aMilestoneOnABarAlwaysHasOne() {
        let milestone = Milestone(title: "Full draft", day: today.adding(5))
        let onBar = HoverCard.milestone(milestone, isNameShown: false, deadline: today.adding(9), now: now)
        #expect(onBar?.title == "Full draft" && lines(onBar).map(\.tone) == [.primary])
        #expect(HoverCard.milestone(milestone, isNameShown: true, deadline: today.adding(9), now: now) == nil)
    }

    @Test func aMilestoneSaysWhenItIsLate() {
        let overdue = Milestone(title: "Results frozen", day: today.adding(-2))
        let card = HoverCard.milestone(overdue, isNameShown: true, deadline: nil, now: now)
        #expect(lines(card).first?.tone == .warning)
        let after = Milestone(title: "Camera-ready", day: today.adding(12))
        let past = HoverCard.milestone(after, isNameShown: true, deadline: today.adding(9), now: now)
        #expect(lines(past).map(\.tone) == [.primary, .alert])
    }

    @Test func aPaperWithNothingToAddHasNone() {
        let paper = Paper(title: "Idea")
        let overview = PaperOverview(paper: paper, catalog: ConferenceCatalog(series: []), now: now)
        #expect(HoverCard.paper(paper, overview: overview, people: [:], now: now) == nil)
    }

    @Test func aPaperListsItsPeopleDeadlinesAndToDos() {
        let deadlines = (1...4).map {
            CustomDeadline(title: "Step \($0)", date: now.addingTimeInterval(Double($0) * 86_400))
        }
        let paper = Paper(
            title: "Video Diffusion", deadlines: deadlines,
            blocks: [
                TimeBlock(kind: .review, start: today.adding(4), end: today.adding(6), people: [jane.id, sam.id]),
                TimeBlock(kind: .writing, start: today, end: today.adding(3), people: [sam.id]),
            ],
            todos: (1...5).map { TodoItem(title: "To-do \($0)") } + [TodoItem(title: "Sent", isDone: true)])
        let overview = PaperOverview(paper: paper, catalog: ConferenceCatalog(series: []), now: now)
        let card = HoverCard.paper(paper, overview: overview, people: [jane.id: jane, sam.id: sam], now: now)
        // Who works on it as their blocks come, each once.
        let with = lines(card).first { $0.text.contains("Jane") }?.text ?? ""
        #expect(with.range(of: "Sam")!.lowerBound < with.range(of: "Jane")!.lowerBound)
        #expect(with.components(separatedBy: "Sam").count == 2)
        #expect(dates(card).count == 3 && dates(card).first?.name == "Step 1")
        let todos = lines(card).filter { $0.symbol == "circle" }
        #expect(todos.map(\.text) == ["To-do 1", "To-do 2", "To-do 3"])
        #expect(lines(card).last?.tone == .tertiary)
    }

    @Test func aPaperNamesItsConferenceWhereTheRowSaysSomethingElse() throws {
        func catalog(paper date: Date?) -> ConferenceCatalog {
            ConferenceCatalog(series: [
                ConferenceSeries(
                    id: "AI/cvpr", title: "CVPR", description: "Computer Vision and Pattern Recognition",
                    category: "AI", ccfRank: "A",
                    editions: [
                        ConferenceEdition(
                            id: "cvpr27", year: 2027, link: "", timeZone: "UTC-12", date: nil, place: nil,
                            rounds: [
                                ConferenceRound(
                                    id: "#1", index: 0, comment: nil, abstract: nil,
                                    paper: DeadlineValue(raw: date == nil ? "TBD" : "", date: date),
                                    rebuttal: nil, decision: nil)
                            ], previous: nil)
                    ])
            ])
        }
        let target = Paper.Target(series: "AI/cvpr", year: 2027)
        let dated = catalog(paper: now.addingTimeInterval(30 * 86_400))
        // Planned or not, its row names the conference, which the card does not repeat.
        for blocks in [[], [TimeBlock(kind: .writing, start: today, end: today)]] {
            let paper = Paper(title: "Sparse Probes", target: target, blocks: blocks)
            let card = HoverCard.paper(
                paper, overview: PaperOverview(paper: paper, catalog: dated, now: now), people: [:], now: now)
            #expect(!lines(card).contains { $0.text == "CVPR 2027" })
            #expect(dates(card).map(\.name) == ["Paper"])
        }
        // A row that says the deadline is not announced.
        let waiting = Paper(title: "Sparse Probes", target: target)
        let card = HoverCard.paper(
            waiting, overview: PaperOverview(paper: waiting, catalog: catalog(paper: nil), now: now), people: [:],
            now: now)
        #expect(lines(card).first?.text == "CVPR 2027")
    }

    @Test func aConferenceSaysWhatItsRowLeavesOut() {
        let row = DeadlineRow(
            id: "cvpr", source: .conference(series: "AI/cvpr", edition: "cvpr27", round: "Round 1"), name: "CVPR",
            year: 2027, roundLabel: "Round 1", abstractDate: now.addingTimeInterval(20 * 86_400),
            paperDate: now.addingTimeInterval(27 * 86_400), rebuttalDate: now.addingTimeInterval(90 * 86_400),
            decisionDate: now.addingTimeInterval(120 * 86_400),
            meeting: MeetingDates(start: Day(year: 2027, month: 6, day: 20), end: Day(year: 2027, month: 6, day: 25)),
            place: "Seattle", state: .scheduled, timeZone: "UTC-12")
        let round = ConferenceRound(
            id: "Round 1", index: 0, comment: "Round 1", abstract: nil, paper: nil, rebuttal: nil, decision: nil)
        let quiet = HoverCard.conference(row, series: nil, round: round, edition: nil, isQuiet: true, now: now)
        let full = HoverCard.conference(row, series: nil, round: round, edition: nil, isQuiet: false, now: now)
        #expect(quiet.title == "CVPR 2027 Round 1")
        #expect(lines(quiet).contains { $0.text.hasPrefix("Seattle") })
        #expect(!lines(full).contains { $0.text.hasPrefix("Seattle") })
        #expect(!lines(quiet).contains { $0.text == "Round 1" })
        #expect(dates(full).map(\.name) == ["Abstract", "Paper", "Rebuttal", "Notification"])
        #expect(dates(full).map(\.state).compactMap { $0 }.count == 2)
    }

    @Test func aFlagOfSeveralDeadlinesLinesThemUp() {
        let deadlines = [DeadlineKind.abstract, .paper].map { kind in
            PaperDeadline(
                id: kind.rawValue, source: .conference(kind),
                value: DeadlineValue(raw: "", date: now.addingTimeInterval(86_400)), timeZone: "UTC-12")
        }
        let card = HoverCard.deadlines(deadlines.map { ($0, "CVPR 2027") }, now: now)
        #expect(card?.title == "CVPR 2027")
        #expect(dates(card).map(\.name) == ["Abstract", "Paper"])
    }
}
