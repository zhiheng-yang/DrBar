import Foundation
import Testing

@testable import DrBarKit

func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> Day {
    Day(year: year, month: month, day: day)
}

@Suite struct PlanMathTests {
    let experiments = TimeBlock(kind: .experiments, start: day(10, 12), end: day(10, 24), isDone: true)  // 13 days
    let writing = TimeBlock(kind: .writing, start: day(10, 25), end: day(11, 7))  // 14 days
    let review = TimeBlock(kind: .review, start: day(11, 8), end: day(11, 14))  // 7 days

    @Test func lengthCountsBothEnds() {
        #expect(experiments.length == 13)
        #expect(TimeBlock(kind: .buffer, start: day(1, 1), end: day(1, 1)).length == 1)
    }

    @Test func progressIsWeightedByDays() {
        #expect(PlanMath.progress([]) == 0)
        #expect(PlanMath.progress([experiments, writing, review]) == 13.0 / 34.0)
    }

    @Test func onOneLineALaterBlockTakesThePlaceOfAnEarlierOne() {
        // Writing over the end of the experiments, and a short task inside a long one.
        #expect(PlanMath.visibleParts([0..<0.5, 0.3..<0.8]) == [[0..<0.3], [0.3..<0.8]])
        #expect(PlanMath.visibleParts([0..<1, 0.2..<0.4]) == [[0..<0.2, 0.4..<1], [0.2..<0.4]])
        // Apart, both show whole; wholly covered, one does not show.
        #expect(PlanMath.visibleParts([0..<0.2, 0.3..<0.5]) == [[0..<0.2], [0.3..<0.5]])
        #expect(PlanMath.visibleParts([0.2..<0.4, 0..<1]) == [[], [0..<1]])
    }

    @Test func status() {
        let blocks = [experiments, writing, review]
        func cutoff(_ day: Day) -> Cutoffs { Cutoffs(days: [day], closesThePlan: true) }
        #expect(PlanMath.status([], today: day(10, 30), cutoffs: .none) == .noPlan)
        #expect(PlanMath.status(blocks, today: day(10, 30), cutoffs: cutoff(day(11, 16))) == .onTrack)
        // Writing is overdue.
        #expect(PlanMath.status(blocks, today: day(11, 10), cutoffs: cutoff(day(11, 16))) == .behind)
        #expect(PlanMath.status(blocks, today: day(10, 30), cutoffs: cutoff(day(11, 10))) == .conflict)
        // Ending on the deadline day is not a conflict.
        #expect(PlanMath.status(blocks, today: day(11, 10), cutoffs: cutoff(day(11, 14))) == .behind)
        #expect(PlanMath.status(blocks, today: day(10, 30), cutoffs: .none) == .onTrack)
        // A milestone that was missed.
        let draft = Milestone(title: "Draft", day: day(10, 28))
        #expect(PlanMath.status(blocks, milestones: [draft], today: day(10, 30), cutoffs: .none) == .behind)
        var sent = draft
        sent.isDone = true
        #expect(PlanMath.status(blocks, milestones: [sent], today: day(10, 30), cutoffs: .none) == .onTrack)
        #expect(PlanMath.nextMilestone([draft, sent], today: day(10, 27)) == draft)
        #expect(PlanMath.nextMilestone([draft], today: day(10, 29)) == nil)
    }

    @Test func currentBlock() {
        let blocks = [experiments, writing, review]
        #expect(PlanMath.currentBlock(blocks, today: day(10, 30))?.kind == .writing)
        // The experiments are done, so the next block to start is current.
        #expect(PlanMath.currentBlock(blocks, today: day(10, 20))?.kind == .writing)
        #expect(PlanMath.currentBlock(blocks, today: day(12, 1)) == nil)
        let overlapping = TimeBlock(kind: .custom, customName: "Figures", start: day(10, 28), end: day(11, 2))
        #expect(PlanMath.currentBlock([overlapping, writing], today: day(10, 30))?.kind == .writing)
    }

    @Test func backwardPlanFromTheDeadline() {
        let plan = PlanMath.backwardPlan(today: day(10, 12), deadline: day(11, 16))
        #expect(plan.map(\.kind) == [.experiments, .writing, .review, .buffer])
        #expect(plan.map(\.length) == [13, 14, 7, 2])
        #expect(plan.first?.start == day(10, 12))
        #expect(plan.last?.end == day(11, 16))
        for (a, b) in zip(plan, plan.dropFirst()) {
            #expect(a.end.adding(1) == b.start)
        }
        #expect(PlanMath.fits(plan, today: day(10, 12)))
    }

    @Test func otherWorkIsPlannedWithoutExperiments() {
        let plan = PlanMath.backwardPlan(today: day(10, 12), deadline: day(11, 16), experiments: false)
        #expect(plan.map(\.kind) == [.writing, .review, .buffer])
        #expect(plan.first?.start == day(10, 25))
        #expect(PlanMath.fits(plan, today: day(10, 12)))
    }

    @Test func backwardPlanWithoutEnoughTime() {
        let plan = PlanMath.backwardPlan(today: day(11, 1), deadline: day(11, 16))
        #expect(plan.map(\.kind) == [.writing, .review, .buffer])
        #expect(!PlanMath.fits(plan, today: day(11, 1)))
        // Exactly enough: experiments get the single remaining day.
        let tight = PlanMath.backwardPlan(today: day(10, 24), deadline: day(11, 16))
        #expect(tight.first?.kind == .experiments)
        #expect(tight.first?.length == 1)
    }
}

@Suite struct BlockDragTests {
    let block = TimeBlock(kind: .writing, start: day(10, 25), end: day(11, 7))

    @Test func theMiddleMovesTheWholeBlock() {
        let moved = block.dragged(.body, by: 3)
        #expect(moved.start == day(10, 28))
        #expect(moved.end == day(11, 10))
        #expect(moved.length == block.length)
        #expect(block.dragged(.body, by: -30).start == day(9, 25))
    }

    @Test func anEndChangesTheLengthButNeverPassesTheOther() {
        #expect(block.dragged(.start, by: -5).start == day(10, 20))
        #expect(block.dragged(.end, by: 2).end == day(11, 9))
        let shortest = block.dragged(.start, by: 40)
        #expect(shortest.start == block.end)
        #expect(shortest.length == 1)
        #expect(block.dragged(.end, by: -40).end == block.start)
        #expect(block.dragged(.start, by: 0) == block)
    }
}

@Suite struct BlockTrackTests {
    func block(_ start: Int, _ end: Int) -> TimeBlock {
        TimeBlock(kind: .writing, start: day(10, start), end: day(10, end))
    }

    @Test func blocksOneAfterAnotherKeepTheWholeBar() {
        let blocks = [block(1, 5), block(6, 9), block(12, 20)]
        #expect(TimeBlock.tracks(of: blocks).values.allSatisfy { $0 == .whole })
    }

    @Test func blocksOnTheSameDaysShareTheBar() {
        let experiments = block(1, 10)
        let writing = block(8, 20)
        let review = block(18, 25)
        let buffer = block(27, 28)
        let tracks = TimeBlock.tracks(of: [writing, buffer, review, experiments])
        // Experiments and writing overlap, and writing and review: two tracks for all three.
        #expect(tracks[experiments.id] == TimeBlock.Track(index: 0, count: 2))
        #expect(tracks[writing.id] == TimeBlock.Track(index: 1, count: 2))
        #expect(tracks[review.id] == TimeBlock.Track(index: 0, count: 2))
        #expect(tracks[buffer.id] == .whole)
    }

    @Test func asManyTracksAsBlocksOnOneDay() {
        let blocks = [block(1, 10), block(2, 3), block(3, 9), block(4, 5)]
        let tracks = TimeBlock.tracks(of: blocks)
        #expect(Set(tracks.values.map(\.count)) == [3])
        #expect(tracks[blocks[3].id]?.index == 1)
    }
}

@Suite struct BlockLaneTests {
    let figures = TimeBlock(kind: .custom, customName: "Figures ", start: day(10, 1), end: day(10, 3))
    let first = TimeBlock(kind: .writing, start: day(10, 5), end: day(10, 18))
    let second = TimeBlock(kind: .writing, start: day(11, 1), end: day(11, 7))
    let moreFigures = TimeBlock(kind: .custom, customName: "Figures", start: day(11, 2), end: day(11, 4))
    let review = TimeBlock(kind: .review, start: day(10, 20), end: day(10, 25))

    @Test func roundsOfOneKindShareALane() {
        let lanes = BlockLane.lanes(of: [figures, first, second, moreFigures, review])
        #expect(lanes.map(\.id) == [.kind(.writing), .kind(.review), .custom("Figures")])
        #expect(lanes[0].blocks == [first, second])
        #expect(lanes[2].blocks == [figures, moreFigures])
    }

    @Test func everyStandardKindHasALaneToDrawIn() {
        let lanes = BlockLane.lanes(of: [figures], includingEmpty: true)
        #expect(
            lanes.map(\.id) == [
                .kind(.experiments), .kind(.writing), .kind(.review), .kind(.buffer), .custom("Figures"),
            ])
        #expect(lanes[1].newBlock(from: day(10, 1), to: day(10, 2)).kind == .writing)
        #expect(lanes[4].newBlock(from: day(10, 1), to: day(10, 2)).customName == "Figures")
        // Other work has no experiments, unless some were planned.
        let experiments = TimeBlock(kind: .experiments, start: day(10, 1), end: day(10, 3))
        #expect(
            BlockLane.lanes(of: [figures, experiments], includingEmpty: true, kinds: BlockLane.workKinds).map(\.id) == [
                .kind(.writing), .kind(.review), .kind(.buffer), .custom("Figures"), .kind(.experiments),
            ])
    }

    @Test func anotherRoundFollowsTheLastOne() {
        let writing = BlockLane.lanes(of: [second, first])[0]
        let round = writing.nextRound(today: day(10, 12))
        #expect(round.kind == .writing)
        #expect(round.start == day(11, 8))
        #expect(round.length == second.length)
        #expect(!round.isDone)
        // Never in the past, and a week in a lane without blocks.
        #expect(writing.nextRound(today: day(12, 1)).start == day(12, 1))
        let empty = BlockLane.lanes(of: [], includingEmpty: true)[3]
        #expect(empty.nextRound(today: day(10, 12)).length == 7)
    }
}

@Suite struct CutoffTests {
    let writing = TimeBlock(kind: .writing, start: day(10, 25), end: day(11, 16))
    let buffer = TimeBlock(kind: .buffer, start: day(11, 15), end: day(11, 16))
    let supplementary = TimeBlock(kind: .custom, customName: "Supplementary", start: day(11, 17), end: day(11, 23))

    @Test func workIsJudgedAgainstTheDeadlineItLeadsUpTo() {
        // The paper deadline on Nov 16, a supplementary on Nov 23.
        let open = Cutoffs(days: [day(11, 23), day(11, 16)], closesThePlan: true)
        #expect(open.days == [day(11, 16), day(11, 23)])
        #expect(!open.runsPast(writing) && !open.runsPast(supplementary))
        #expect(open.deadline(for: supplementary) == day(11, 23))
        // Across a deadline, or wholly after the last while the main one is open.
        #expect(open.runsPast(TimeBlock(kind: .writing, start: day(11, 10), end: day(11, 18))))
        #expect(open.runsPast(TimeBlock(kind: .buffer, start: day(11, 24), end: day(11, 25))))
        // A buffer left two days past a paper deadline that moved two days earlier.
        let moved = Cutoffs(days: [day(11, 14)], closesThePlan: true)
        #expect(moved.runsPast(buffer))
        // Once submitted, work after every deadline is not late.
        let submitted = Cutoffs(days: [day(12, 2)], closesThePlan: false)
        #expect(!submitted.runsPast(TimeBlock(kind: .custom, customName: "Talk", start: day(12, 10), end: day(12, 12))))
        #expect(
            submitted.runsPast(TimeBlock(kind: .custom, customName: "Rebuttal", start: day(11, 25), end: day(12, 3))))
        #expect(submitted.deadline(for: day(12, 10)) == nil)
        #expect(Cutoffs.none.deadline(for: writing) == nil && !Cutoffs.none.runsPast(writing))
    }

    @Test func movingADeadlineEarlierThanItsWorkIsAConflict() {
        let zone = TimeZone.current
        let workshop = CustomDeadline(
            title: "Workshop", date: date("2026-11-20 12:00", zone), timeZone: zone.identifier)
        let paper = Paper(title: "P", deadlines: [workshop], mainDeadline: workshop.id, blocks: [writing])
        let now = date("2026-10-12 12:00", zone)
        #expect(!paper.wouldRunPast(movingDeadline: workshop.id, byDays: -4, catalog: .empty, now: now))
        #expect(paper.wouldRunPast(movingDeadline: workshop.id, byDays: -5, catalog: .empty, now: now))
        #expect(!paper.wouldRunPast(movingDeadline: UUID(), byDays: -5, catalog: .empty, now: now))
    }
}

@Suite struct RowMoveTests {
    @Test func theRowLandsWhereItIsLetGo() {
        #expect(RowMove(from: 0, translation: 50).destination(rowHeight: 44, count: 4) == 1)
        #expect(RowMove(from: 0, translation: 20).destination(rowHeight: 44, count: 4) == 0)
        #expect(RowMove(from: 3, translation: -500).destination(rowHeight: 44, count: 4) == 0)
        #expect(RowMove(from: 1, translation: 500).destination(rowHeight: 44, count: 4) == 3)
    }

    @Test func theRowsItPassesStepAside() {
        let down = RowMove(from: 0, translation: 90)  // lands on 2
        #expect([0, 1, 2, 3].map { down.offset(ofRowAt: $0, rowHeight: 44, count: 4) } == [90, -44, -44, 0])
        let up = RowMove(from: 3, translation: -45)  // lands on 2
        #expect([0, 1, 2, 3].map { up.offset(ofRowAt: $0, rowHeight: 44, count: 4) } == [0, 0, 44, -45])
    }

    @Test func rowsOfDifferentHeights() {
        let heights = [64.0, 108, 64, 64]
        // Down past the tall row once the dragged row's bottom edge is past its middle, 54 pt down.
        #expect(RowMove(from: 0, translation: 50).destination(heights: heights) == 0)
        #expect(RowMove(from: 0, translation: 60).destination(heights: heights) == 1)
        let down = RowMove(from: 0, translation: 120)
        #expect([0, 1, 2, 3].map { down.offset(ofRowAt: $0, heights: heights) } == [120, -64, 0, 0])
        #expect(down.landing(heights: heights) == 108)
        // The tall row dragged up lands above the first once its top passes the first's middle.
        #expect(RowMove(from: 1, translation: -33).destination(heights: heights) == 0)
        #expect(RowMove(from: 1, translation: -33).landing(heights: heights) == -64)
        #expect(RowMove(from: 1, translation: -30).destination(heights: heights) == 1)
        #expect(
            RowMove(from: 1, translation: 70).apply(to: ["a", "b", "c", "d"], heights: heights) == ["a", "c", "b", "d"])
    }

    @Test func newOrder() {
        #expect(
            RowMove(from: 0, translation: 90).apply(to: ["a", "b", "c", "d"], rowHeight: 44) == ["b", "c", "a", "d"])
        // Rows that were not shown keep their places.
        #expect(RowMove.merge(["d", "a", "c"], into: ["a", "b", "c", "d"]) == ["d", "b", "a", "c"])
    }
}

@Suite struct LabelPlacementTests {
    func mark(_ x: Double, _ width: Double, _ rank: Int = 1) -> LabelPlacement.Mark {
        LabelPlacement.Mark(
            x: x, width: width, rank: rank,
            clearance: rank == 0 ? LabelPlacement.nearClearance : LabelPlacement.clearance)
    }

    @Test func aNameGoesAfterItsMarkOrBeforeItAtTheEdge() {
        #expect(LabelPlacement.place([mark(100, 80)], width: 400) == [.init(side: .after, width: 80)])
        #expect(LabelPlacement.place([mark(340, 80)], width: 400) == [.init(side: .before, width: 80)])
        // At the very end the mark faces back, its name before it.
        #expect(
            LabelPlacement.place([mark(395, 80)], width: 400) == [.init(side: .before, width: 80, isMirrored: true)])
    }

    @Test func theCVPRTrioAtThreeMonths() {
        // About 7.6 pt a day: the abstract a week before the paper deadline, the supplementary a
        // week after. The flag is named first and in full; the others take what is left.
        let placed = LabelPlacement.place([mark(100, 46), mark(153, 30, 0), mark(206, 130)], width: 600)
        #expect(placed[0] == .init(side: .before, width: 46))
        #expect(placed[1] == .init(side: .after, width: 30))
        #expect(placed[2] == .init(side: .after, width: 130))
    }

    @Test func theFlagIsNamedInTheWindowsFirstSize() {
        // About 6.3 pt a day in a window of 1,100 pt: the abstract six days before the paper
        // deadline, the supplementary a week after. The red name may come closer to the next flag.
        let placed = LabelPlacement.place([mark(100, 42), mark(138, 28, 0), mark(182, 115)], width: 600)
        #expect(placed[1] == .init(side: .after, width: 28))
        #expect(placed[0].side == .before && placed[2].side == .after)
        // A gray name keeps its distance.
        #expect(LabelPlacement.place([mark(138, 28), mark(182, 115)], width: 600)[0].side != .after)
    }

    @Test func theFlagKeepsItsNameWhileOthersGiveWay() {
        let placed = LabelPlacement.place([mark(20, 80), mark(80, 80, 0), mark(125, 80)], width: 160)
        // The flag's whole name would not fit after it, so it goes before it, cut to the room
        // there; the others then find no room worth a name.
        #expect(placed[1].side == .before && placed[1].width >= 36)
        #expect(placed[0].side == nil && placed[2].side == nil)
        #expect(LabelPlacement.place([mark(5, 80)], width: 30) == [.init(side: nil, width: 0)])
        // A short name is shown whole or not at all.
        #expect(LabelPlacement.place([mark(100, 42), mark(138, 30, 0), mark(178, 115)], width: 600)[1].side == nil)
    }

    @Test func whereNamesCannotBeHoveredTheMarksInTheWayGiveWayToTheFlag() {
        // The email's image: about 4 pt a day.
        let marks = [mark(100, 96), mark(124, 120, 0), mark(152, 115), mark(300, 40)]
        let left = LabelPlacement.yielding(marks, width: 400)
        #expect(left == [2])
        let kept = marks.indices.filter { !left.contains($0) }.map { marks[$0] }
        #expect(LabelPlacement.place(kept, width: 400)[1] == .init(side: .after, width: 120))
        #expect(LabelPlacement.yielding([mark(100, 30, 0), mark(200, 30)], width: 400).isEmpty)
        // Without a flag, nothing gives way.
        #expect(LabelPlacement.yielding([mark(100, 96), mark(124, 120), mark(152, 115)], width: 400).isEmpty)
    }

    @Test func theFlagBeyondTheAxisIsNamedAtItsEdge() {
        // Its arrow stands a point inside the end it points past, named toward the middle, and a
        // flag near it keeps clear of its name.
        let right = LabelPlacement.place([mark(330, 80), mark(399, 50, 0)], width: 400)
        #expect(right[1] == .init(side: .before, width: 46, isMirrored: true))
        #expect(right[0] == .init(side: .before, width: 80))
        let left = LabelPlacement.place([mark(1, 50, 0), mark(70, 80)], width: 400)
        #expect(left == [.init(side: .after, width: 50), .init(side: .after, width: 80)])
    }

    @Test func marksCloseTogetherStandAsOne() {
        #expect(LabelPlacement.clusters([103, 100, 200], width: 400) == [[1, 0], [2]])
        // At the end of the line a mark faces back, toward one that would otherwise stand apart.
        #expect(LabelPlacement.clusters([588, 599], width: 600) == [[0, 1]])
        #expect(LabelPlacement.clusters([570, 599], width: 600) == [[0], [1]])
    }
}

/// A catalog of one edition with one round, `cvpr27` unless named otherwise, in UTC-12.
func catalog(
    series: String = "AI/cvpr", title: String = "CVPR", edition: String = "cvpr27", abstract: DeadlineValue? = nil,
    paper: DeadlineValue? = cvprPaper, rebuttal: DeadlineValue? = nil, decision: DeadlineValue? = nil
) -> ConferenceCatalog {
    let round = ConferenceRound(
        id: "#1", index: 0, comment: nil, abstract: abstract, paper: paper, rebuttal: rebuttal, decision: decision)
    let edition = ConferenceEdition(
        id: edition, year: 2027, link: "https://example.org", timeZone: "UTC-12", date: nil, place: nil,
        rounds: [round], previous: nil)
    return ConferenceCatalog(series: [
        ConferenceSeries(
            id: series, title: title, description: "", category: "AI", ccfRank: "A", editions: [edition])
    ])
}

let cvprAbstract = DeadlineValue(raw: "2026-11-10 23:59:59", date: date("2026-11-11 11:59"))
let cvprPaper = DeadlineValue(raw: "2026-11-16 23:59:59", date: date("2026-11-17 11:59"))
let cvprRebuttal = DeadlineValue(raw: "2027-02-01 23:59:59", date: date("2027-02-02 11:59"))
let cvprDecision = DeadlineValue(raw: "2027-02-25 23:59:59", date: date("2027-02-26 11:59"))

@Suite struct ProgressSummaryTests {
    let now = date("2026-10-30 10:00", TimeZone(identifier: "Europe/Amsterdam")!)

    var paper: Paper {
        Paper(
            title: "Efficient Video Diffusion", target: Paper.Target(series: "AI/cvpr", year: 2027), stage: .writing,
            blocks: [
                TimeBlock(kind: .experiments, start: day(10, 12), end: day(10, 24), isDone: true),
                TimeBlock(kind: .writing, start: day(10, 25), end: day(11, 7)),
                TimeBlock(kind: .review, start: day(11, 8), end: day(11, 14)),
                TimeBlock(kind: .buffer, start: day(11, 15), end: day(11, 16)),
            ],
            milestones: [
                Milestone(title: "Results frozen", day: day(10, 20), isDone: true),
                Milestone(title: "Internal deadline", day: day(11, 12)),
                Milestone(title: "Full draft to Jane ", day: day(11, 1)),
            ])
    }

    func deadlines(_ paper: Paper, in catalog: ConferenceCatalog = catalog()) -> PaperDeadlines {
        PaperDeadlines.resolve(paper, catalog: catalog, now: now, calendar: amsterdam)
    }

    func text(_ paper: Paper, _ deadlines: PaperDeadlines, _ language: MailLanguage = .english) -> String {
        ProgressSummary.text(
            paper: paper, deadlines: deadlines, language: language, hidesBufferBlocks: true, now: now,
            calendar: amsterdam)
    }

    @Test func englishSummary() {
        #expect(
            text(paper, deadlines(paper)) == """
                Target: CVPR 2027 — paper deadline 16 Nov, 23:59 (UTC-12)
                Done: Experiments (12 Oct – 24 Oct)
                Now: Writing (25 Oct – 7 Nov)
                Next: Internal review (8 Nov – 14 Nov)
                Due: Full draft to Jane (1 Nov)
                """)
    }

    @Test func unnamedBlocksAndMilestonesAreCalledAsTheAppCallsThem() {
        var unnamed = paper
        unnamed.blocks[1] = TimeBlock(kind: .custom, start: day(10, 25), end: day(11, 7))
        unnamed.milestones[2].title = " "
        let english = text(unnamed, deadlines(unnamed))
        #expect(
            english.contains("Now: Untitled block (25 Oct – 7 Nov)")
                && english.contains("Due: Untitled milestone (1 Nov)"))
        let chinese = text(unnamed, deadlines(unnamed), .chinese)
        #expect(chinese.contains("未命名时间块") && chinese.contains("未命名里程碑"))
    }

    @Test func theTargetLineRunsFromTheNextDeadlineToTheMainOne() {
        let withAbstract = deadlines(paper, in: catalog(abstract: cvprAbstract))
        #expect(
            text(paper, withAbstract).hasPrefix(
                "Target: CVPR 2027 — abstract deadline 10 Nov, 23:59 · paper deadline 16 Nov, 23:59 (UTC-12)"))
        // Each in its own time zone, after those that share it.
        var mixed = paper
        mixed.target = nil
        mixed.deadlines = [
            CustomDeadline(title: "Workshop", date: date("2026-11-21 11:59"), timeZone: "UTC-12"),
            CustomDeadline(title: "Abstract", date: date("2026-11-16 22:59"), timeZone: "UTC+1"),
        ]
        mixed.mainDeadline = mixed.deadlines[0].id
        #expect(
            text(mixed, deadlines(mixed)).hasPrefix(
                "Target: Abstract 16 Nov, 23:59 (UTC+1) · Workshop 20 Nov, 23:59 (UTC-12)"))
    }

    @Test func theImageNamesEachDeadline() {
        let all = deadlines(paper, in: catalog(abstract: cvprAbstract, rebuttal: cvprRebuttal)).all
        let english = MailStrings(.english)
        let chinese = MailStrings(.chinese)
        #expect(all.map { english.label(of: $0) } == ["Abstract deadline", "Paper deadline", "Rebuttal"])
        #expect(all.map { chinese.label(of: $0) } == ["摘要截止", "全文截止", "Rebuttal"])
        // The marked one with its venue, for recipients who see no header.
        let conference = deadlines(paper).conference
        #expect(english.label(of: all[1], conference: conference) == "CVPR 2027 paper deadline")
        // An own deadline as it was typed, and one without a name.
        let own = PaperDeadline(
            id: "own", source: .own(UUID()), title: "camera-ready", value: DeadlineValue(raw: "", date: now),
            timeZone: "AoE")
        #expect(english.label(of: own) == "camera-ready")
        var unnamed = own
        unnamed.title = ""
        #expect(english.label(of: unnamed) == "Deadline" && chinese.label(of: unnamed) == "截止")
    }

    @Test func localTimeIsWrittenWithItsOffsetOnTheDay() {
        var mixed = paper
        mixed.target = nil
        mixed.deadlines = [
            // 23:59 in Amsterdam, before the clocks go back on Oct 25 and after.
            CustomDeadline(title: "Draft", date: date("2026-10-23 21:59"), timeZone: "Europe/Amsterdam"),
            CustomDeadline(title: "Figures", date: date("2026-11-01 22:59"), timeZone: "Europe/Amsterdam"),
            CustomDeadline(title: "Workshop", date: date("2026-11-21 11:59"), timeZone: "UTC-12"),
        ]
        mixed.mainDeadline = mixed.deadlines[2].id
        let early = date("2026-10-20 10:00")
        let text = ProgressSummary.text(
            paper: mixed, deadlines: PaperDeadlines.resolve(mixed, catalog: catalog(), now: early, calendar: amsterdam),
            language: .english, hidesBufferBlocks: true, now: early, calendar: amsterdam)
        #expect(
            text.hasPrefix(
                "Target: Draft 23 Oct, 23:59 (UTC+2) · Figures 1 Nov, 23:59 (UTC+1) · Workshop 20 Nov, 23:59 (UTC-12)"))
    }

    @Test func blocksNameThePeopleOnThem() {
        let sam = Person(name: "Sam Lee", email: "sam@example.org")
        let mia = Person(name: "Mia Chen", email: "mia@example.org")
        var paper = paper
        paper.blocks[1].people = [sam.id, mia.id, UUID()]
        let people = [sam.id: sam, mia.id: mia]
        let english = ProgressSummary.text(
            paper: paper, deadlines: deadlines(paper), language: .english, hidesBufferBlocks: true, people: people,
            now: now, calendar: amsterdam)
        #expect(english.contains("Now: Writing (25 Oct – 7 Nov, with Sam Lee and Mia Chen)"))
        let chinese = ProgressSummary.text(
            paper: paper, deadlines: deadlines(paper), language: .chinese, hidesBufferBlocks: true, people: people,
            now: now, calendar: amsterdam)
        #expect(chinese.contains("进行中：写作（10月25日 – 11月7日，与 Sam Lee和Mia Chen）"))
    }

    @Test func chineseSummary() {
        #expect(
            text(paper, deadlines(paper), .chinese) == """
                目标：CVPR 2027 — 全文截止 11月16日 23:59（UTC-12）
                已完成：实验（10月12日 – 10月24日）
                进行中：写作（10月25日 – 11月7日）
                下一步：内审修改（11月8日 – 11月14日）
                里程碑：Full draft to Jane（11月1日）
                """)
    }

    @Test func subjectTellsTheDaysLeftRoundedDown() {
        let cvpr = deadlines(paper)
        func suffix(at now: Date, _ deadlines: PaperDeadlines = cvpr, language: MailLanguage = .english) -> String {
            ProgressSummary.subjectSuffix(deadlines, language: language, now: now)
        }
        #expect(suffix(at: now) == " (18 days to the CVPR 2027 paper deadline)")
        #expect(suffix(at: now, language: .chinese) == "（距 CVPR 2027 全文截止还有 18 天）")
        // Four and a half days are four.
        #expect(suffix(at: date("2026-11-12 23:59")) == " (4 days to the CVPR 2027 paper deadline)")
        #expect(suffix(at: date("2026-11-17 01:00")) == " (less than a day to the CVPR 2027 paper deadline)")
        let withAbstract = deadlines(paper, in: catalog(abstract: cvprAbstract))
        #expect(suffix(at: now, withAbstract) == " (12 days to the CVPR 2027 abstract deadline)")
        var decided = paper
        decided.stage = .decided
        #expect(suffix(at: now, deadlines(decided)).isEmpty)
        // A deadline of its own goes by its name.
        var cameraReady = decided
        cameraReady.deadlines = [CustomDeadline(title: "Camera-ready", date: date("2026-11-22 11:59"))]
        #expect(suffix(at: now, deadlines(cameraReady)) == " (23 days to Camera-ready)")
        #expect(suffix(at: now, deadlines(cameraReady), language: .chinese) == "（距 Camera-ready 还有 23 天）")
    }

    @Test func bufferBlocksCanBeIncluded() {
        let late = date("2026-11-14 10:00", amsterdam.timeZone)
        let hidden = ProgressSummary.text(
            paper: paper, deadlines: PaperDeadlines(), language: .english, hidesBufferBlocks: true, now: late,
            calendar: amsterdam)
        #expect(!hidden.contains("Buffer"))
        let shown = ProgressSummary.text(
            paper: paper, deadlines: PaperDeadlines(), language: .english, hidesBufferBlocks: false, now: late,
            calendar: amsterdam)
        #expect(shown.hasSuffix("Next: Buffer (15 Nov – 16 Nov)"))
    }

    @Test func targetLineAfterSubmissionAndWhenNotAnnounced() {
        var submitted = paper
        submitted.stage = .submitted
        let withDecision = deadlines(submitted, in: catalog(decision: cvprDecision))
        #expect(
            text(submitted, withDecision).hasPrefix("Target: CVPR 2027 — submitted · decision 25 Feb, 23:59 (UTC-12)"))
        // A supplementary of its own comes first after submitting.
        var supplementary = submitted
        supplementary.deadlines = [
            CustomDeadline(title: "Supplementary", date: date("2026-11-24 11:59"), timeZone: "UTC-12")
        ]
        #expect(
            text(supplementary, deadlines(supplementary, in: catalog(decision: cvprDecision))).hasPrefix(
                "Target: CVPR 2027 — submitted · Supplementary 23 Nov, 23:59 (UTC-12)"))

        var colt = paper
        colt.target = Paper.Target(series: "CT/colt", year: 2027)
        let tbd = catalog(
            series: "CT/colt", title: "COLT", edition: "colt27", paper: DeadlineValue(raw: "TBD", date: nil))
        #expect(text(colt, deadlines(colt, in: tbd)).hasPrefix("Target: COLT 2027 — deadline not announced yet"))
    }

    @Test func ownDeadlineWithoutAName() {
        var own = paper
        own.target = nil
        own.deadlines = [CustomDeadline(title: "", date: date("2026-11-17 11:59"), timeZone: "UTC-12")]
        own.mainDeadline = own.deadlines[0].id
        let deadlines = deadlines(own)
        #expect(text(own, deadlines).hasPrefix("Target: deadline 16 Nov, 23:59 (UTC-12)"))
        #expect(ProgressSummary.subjectSuffix(deadlines, language: .english, now: now) == " (18 days to the deadline)")
        #expect(ProgressSummary.subjectSuffix(deadlines, language: .chinese, now: now) == "（距截止还有 18 天）")
        #expect(deadlines.main.map { MailStrings(.english).name(of: $0) } == "deadline")
    }

    @Test func bodyJoinsTheNonEmptyParts() {
        #expect(
            ProgressSummary.body(headline: "On track.", message: "  Hi!\n", summary: "Target: X", signature: "Ada")
                == "On track.\n\nHi!\n\nTarget: X\n\nAda")
        #expect(ProgressSummary.body(message: "", summary: nil, signature: "Ada") == "Ada")
    }

    @Test func subjectNamesTheStageToo() {
        #expect(
            ProgressSummary.subjectSuffix(deadlines(paper), current: paper.blocks[1], language: .english, now: now)
                == " (Writing · 18 days to the CVPR 2027 paper deadline)")
        #expect(
            ProgressSummary.subjectSuffix(PaperDeadlines(), current: paper.blocks[1], language: .chinese, now: now)
                == "（写作）")
        let countdown = ProgressSummary.countdown(deadlines(paper), language: .english, now: now)
        #expect(countdown?.days == 18)
        #expect(countdown?.caption == "to the CVPR 2027 paper deadline")
        #expect(
            ProgressSummary.countdown(deadlines(paper), language: .chinese, now: now)?.caption == "距 CVPR 2027 全文截止")
    }

    @Test func theFirstLineSaysWhatMattersToTheRecipients() {
        let jane = UUID()
        var paper = paper
        paper.blocks[2].people = [jane]  // the internal review, 8 – 14 Nov
        func headline(
            _ paper: Paper, at now: Date, status: PlanStatus = .onTrack, to recipients: Set<UUID> = [jane],
            since: Date? = nil, language: MailLanguage = .english
        ) -> String {
            ProgressSummary.headline(
                paper: paper, status: status, recipients: recipients, lastUpdate: since, language: language,
                hidesBufferBlocks: true, now: now, calendar: amsterdam)
        }
        // Their review is two weeks away or less.
        #expect(headline(paper, at: now) == "Internal review with you starts on 8 Nov.")
        #expect(headline(paper, at: now, language: .chinese) == "与您一起的内审修改将于 11月8日 开始。")
        // Under way, and what happened since the last update.
        let during = date("2026-11-10 10:00", amsterdam.timeZone)
        #expect(
            headline(paper, at: during, since: date("2026-10-20 10:00", amsterdam.timeZone))
                == "Internal review with you is under way, until 14 Nov. Since 20 Oct: Experiments done, Writing started."
        )
        // Someone else's update leads with how the plan stands.
        #expect(headline(paper, at: now, to: []) == "On track: Writing until 7 Nov.")
        var late = paper
        late.blocks[1].end = Day(year: 2026, month: 10, day: 28)
        #expect(
            headline(late, at: now, status: .behind, to: [])
                == "Behind schedule: Writing was planned to end on 28 Oct.")
        #expect(headline(paper, at: now, status: .conflict, to: []) == "The plan runs past the deadline.")
    }

    @Test func subjects() {
        #expect(MailStrings(.english).defaultSubject(paperTitle: "Video") == "Progress: Video")
        #expect(ProgressSummary.replySubject("Progress: Video") == "Re: Progress: Video")
        #expect(ProgressSummary.replySubject("Re: Progress: Video") == "Re: Progress: Video")
    }
}

@Suite struct OtherWorkTests {
    let now = date("2026-10-30 10:00", TimeZone(identifier: "Europe/Amsterdam")!)
    let jane = Person(name: "Jane", email: "jane@example.org")
    let sam = Person(name: "Sam", email: "sam@example.org")
    let applications = ItemGroup(name: "Applications")

    /// The update's own paper, two papers and an item that Jane may hear about, the item also Sam,
    /// and what never goes out: decided with nothing ahead, untitled, or archived.
    let data: UserData

    init() {
        let cvpr = Paper.Target(series: "AI/cvpr", year: 2027)
        let letters = CustomDeadline(title: "Letters", date: date("2026-12-01 22:59"), timeZone: "Europe/Amsterdam")
        let cameraReady = CustomDeadline(title: "Camera-ready", date: date("2026-11-21 11:59"), timeZone: "UTC-12")
        let proposal = TimeBlock(kind: .custom, customName: "Research proposal", start: day(11, 3), end: day(11, 13))
        data = UserData(
            papers: [
                Paper(title: "Video Diffusion", target: cvpr, visibleTo: [jane.id]),
                Paper(
                    title: "RL Benchmark", target: cvpr, stage: .experiments,
                    blocks: [TimeBlock(kind: .experiments, start: day(10, 20), end: day(11, 14))],
                    visibleTo: [jane.id]),
                Paper(title: "Old Paper", stage: .decided, visibleTo: [jane.id]),
                Paper(
                    title: "Sparse Probes", target: cvpr, deadlines: [cameraReady], stage: .decided,
                    visibleTo: [jane.id]),
                Paper(title: " ", visibleTo: [jane.id]),
                Paper(
                    title: "Doctoral Fellowship", deadlines: [letters], mainDeadline: letters.id, blocks: [proposal],
                    visibleTo: [jane.id, sam.id], groupID: applications.id),
            ],
            groups: [applications], archive: [Paper(title: "Archived", visibleTo: [jane.id])])
    }

    func work(_ recipients: [Person], in data: UserData? = nil) -> [String] {
        (data ?? self.data).work(
            visibleTo: recipients, besides: self.data.papers[0].id, catalog: catalog(), now: now, calendar: amsterdam
        ).map(\.paper.title)
    }

    @Test func onlyWhatEveryRecipientMaySee() {
        #expect(work([jane]) == ["RL Benchmark", "Sparse Probes", "Doctoral Fellowship"])
        #expect(work([jane, sam]) == ["Doctoral Fellowship"])
        #expect(work([]).isEmpty)
        // Someone without an address gets no email, so they do not count.
        let group = RecipientGroup(kind: .collaborators, people: [sam, Person(name: "Li")])
        #expect(work(group.recipients) == ["Doctoral Fellowship"])
    }

    @Test func inTheOrderOfTheSidebar() {
        var data = data
        data.papersPosition = 1
        #expect(work([jane], in: data) == ["Doctoral Fellowship", "RL Benchmark", "Sparse Probes"])
    }

    @Test func aLineForEach() {
        let work = data.work(
            visibleTo: [jane], besides: data.papers[0].id, catalog: catalog(), now: now, calendar: amsterdam)
        func text(_ language: MailLanguage) -> String? {
            ProgressSummary.otherWork(work, language: language, hidesBufferBlocks: true, now: now, calendar: amsterdam)
        }
        #expect(
            text(.english) == """
                Also working on:
                RL Benchmark (CVPR 2027) — Experiments until 14 Nov · paper deadline 16 Nov
                Sparse Probes (CVPR 2027) — decided · Camera-ready 20 Nov
                Doctoral Fellowship — Research proposal from 3 Nov · Letters 1 Dec
                """)
        #expect(
            text(.chinese) == """
                同时在做：
                RL Benchmark（CVPR 2027） — 实验进行到 11月14日 · 全文截止 11月16日
                Sparse Probes（CVPR 2027） — 已出结果 · Camera-ready 11月20日
                Doctoral Fellowship — Research proposal 将于 11月3日 开始 · Letters 12月1日
                """)
        #expect(ProgressSummary.otherWork([], language: .english, hidesBufferBlocks: true, now: now) == nil)
    }

    @Test func nothingElseOfThemGoesOut() {
        var paper = data.papers[1]
        paper.notes = "secret notes"
        paper.todos = [TodoItem(title: "secret to-do")]
        paper.milestones = [Milestone(title: "secret milestone", day: day(11, 2))]
        paper.blocks[0].people = [sam.id]
        paper.blocks.append(TimeBlock(kind: .buffer, start: day(10, 29), end: day(10, 31)))
        paper.blocks[0].start = day(11, 1)
        let deadlines = PaperDeadlines.resolve(paper, catalog: catalog(), now: now, calendar: amsterdam)
        func text(hidingBuffers: Bool) -> String {
            ProgressSummary.otherWork(
                [(paper, deadlines)], language: .english, hidesBufferBlocks: hidingBuffers, now: now,
                calendar: amsterdam) ?? ""
        }
        #expect(!text(hidingBuffers: true).contains("secret") && !text(hidingBuffers: true).contains("Sam"))
        #expect(text(hidingBuffers: true).contains("Experiments from 1 Nov"))
        #expect(text(hidingBuffers: false).contains("Buffer until 31 Oct"))
    }

    @Test func theBodyTellsOfOtherWorkAfterTheSummary() {
        #expect(
            ProgressSummary.body(headline: "H", message: "M", summary: "S", otherWork: "O", signature: "A")
                == "H\n\nM\n\nS\n\nO\n\nA")
    }
}

/// Which round a paper follows, and when its round is fixed or let go.
@Suite struct RoundTests {
    let target = Paper.Target(series: "DB/sigmod", year: 2027)

    /// An edition whose rounds close at 23:59 UTC on `days`, `nil` for one not announced yet.
    func edition(year: Int = 2027, meeting: MeetingDates? = nil, _ days: [String?]) -> ConferenceEdition {
        let rounds = days.enumerated().map { index, day in
            ConferenceRound(
                id: "#\(index + 1)", index: index, comment: nil, abstract: nil,
                paper: DeadlineValue(raw: day.map { "\($0) 23:59:59" } ?? "TBD", date: day.map { date("\($0) 23:59") }),
                rebuttal: nil, decision: nil)
        }
        return ConferenceEdition(
            id: "sigmod\(year % 100)", year: year, link: "", timeZone: "UTC", date: nil, place: nil, meeting: meeting,
            rounds: rounds, previous: nil)
    }

    func catalog(_ edition: ConferenceEdition) -> ConferenceCatalog {
        ConferenceCatalog(series: [
            ConferenceSeries(
                id: "DB/sigmod", title: "SIGMOD", description: "", category: "DB", ccfRank: "A", editions: [edition])
        ])
    }

    @Test func aRoundNotAnnouncedIsToComeOnlyUntilTheConferenceMeets() {
        let now = date("2026-10-12 12:00")
        // A conference of last year that never gave its second round a date.
        let past = edition(year: 2025, ["2024-11-06", nil])
        #expect(past.isOver(now: now) && past.pendingRound(now: now) == nil)
        #expect(past.round(id: nil, now: now)?.id == "#1")
        let coming = edition(["2026-09-01", nil])
        #expect(!coming.isOver(now: now) && coming.round(id: nil, now: now)?.id == "#2")
        // This year's, by its days.
        let met = edition(year: 2026, meeting: MeetingDates(start: day(7, 14), end: day(7, 16)), ["2026-02-01", nil])
        #expect(met.isOver(now: now) && met.round(id: nil, now: now)?.id == "#1")
        let meets = edition(
            year: 2026, meeting: MeetingDates(start: day(12, 14), end: day(12, 16)), ["2026-08-01", nil])
        #expect(!meets.isOver(now: now) && meets.round(id: nil, now: now)?.id == "#2")
        // The lists agree.
        func notAnnounced(_ edition: ConferenceEdition) -> [String] {
            DeadlineRows.build(catalog: catalog(edition), following: Following(starredSeries: ["DB/sigmod"]), now: now)
                .filter { $0.state == .notAnnounced }.map(\.id)
        }
        #expect(notAnnounced(met).isEmpty && notAnnounced(meets) == ["sigmod26|#2"])
    }

    @Test func theRoundToComeIsTheOneThatClosesFirst() throws {
        // ccfddl lists the winter round before the autumn one.
        let unordered = edition(["2027-01-15", "2026-10-22"])
        let now = date("2026-10-12 12:00")
        #expect(unordered.round(id: nil, now: now)?.id == "#2")
        let series = try #require(catalog(unordered).series.first)
        let choice = TargetChoice(series: series, edition: unordered, isStarred: false, now: now)
        #expect(choice.deadline == date("2026-10-22 23:59") && choice.roundLabel == "#2")
        // Once both have passed, the last to close.
        #expect(unordered.round(id: nil, now: date("2027-02-01 12:00"))?.id == "#1")
    }

    @Test func aPaperGoesToTheRoundItIsSubmittedTo() {
        let sigmod = catalog(edition(["2026-07-17", "2026-10-17", "2026-12-01"]))
        var data = UserData(papers: [Paper(title: "P", target: target, stage: .writing)])
        let id = data.papers[0].id
        data.setStage(.submitted, of: id, catalog: sigmod, now: date("2026-07-17 20:00"))
        data.setStage(.decided, of: id, catalog: sigmod, now: date("2026-09-01 12:00"))
        #expect(data.papers[0].target?.round == "#1")
        // Back to Submitted, as when Decided was picked by mistake, it keeps its round.
        data.setStage(.submitted, of: id, catalog: sigmod, now: date("2026-10-18 09:00"))
        #expect(data.papers[0].target?.round == "#1")
        // Worked on again and submitted again, it goes to the round of then.
        data.setStage(.decided, of: id, catalog: sigmod, now: date("2026-10-18 09:00"))
        data.setStage(.writing, of: id, catalog: sigmod, now: date("2026-10-18 09:00"))
        #expect(data.papers[0].target?.round == nil)
        data.setStage(.submitted, of: id, catalog: sigmod, now: date("2026-12-01 20:00"))
        #expect(data.papers[0].target?.round == "#3")
        // Decided straight from writing, it went in by the round nearest then.
        var straight = UserData(papers: [Paper(title: "Q", target: target, stage: .writing)])
        straight.setStage(.decided, of: straight.papers[0].id, catalog: sigmod, now: date("2026-10-18 09:00"))
        #expect(straight.papers[0].target?.round == "#2")
    }

    @Test func takingTheSubmissionBackLetsGoOfItsRound() {
        let sigmod = catalog(edition(["2026-07-17", "2026-10-17", "2026-12-01"]))
        var data = UserData(papers: [Paper(title: "P", target: target, stage: .writing)])
        let id = data.papers[0].id
        // Marked submitted by mistake, and taken back before the round closes.
        data.setStage(.submitted, of: id, catalog: sigmod, now: date("2026-10-12 12:00"))
        #expect(data.papers[0].target?.round == "#2")
        data.setStage(.writing, of: id, catalog: sigmod, now: date("2026-10-13 12:00"))
        let deadlines = PaperDeadlines.resolve(data.papers[0], catalog: sigmod, now: date("2026-10-20 12:00"))
        #expect(data.papers[0].target?.round == nil && deadlines.main?.date == date("2026-12-01 23:59"))
    }

    @Test func aRoundChosenStaysUntilAnotherIsChosen() {
        let sigmod = catalog(edition(["2026-07-17", "2026-10-17", "2026-12-01"]))
        var chosen = target
        chosen.round = "#2"
        var data = UserData(papers: [Paper(title: "P", target: chosen, stage: .writing)])
        let id = data.papers[0].id
        // Gone in by October's round, but marked submitted only weeks later.
        data.setStage(.submitted, of: id, catalog: sigmod, now: date("2026-11-30 12:00"))
        #expect(data.papers[0].target?.round == "#2")
        let pinned = data.pinSubmittedRounds(in: sigmod, now: date("2026-12-02 12:00"))
        #expect(!pinned && data.papers[0].target?.round == "#2")
    }
}

@Suite struct ReminderPlannerTests {
    let now = date("2026-10-12 12:00")
    var settings: AppSettings {
        var settings = AppSettings()
        settings.notificationsEnabled = true
        return settings
    }

    func row(_ id: String, paper: Date, abstract: Date? = nil) -> DeadlineRow {
        DeadlineRow(
            id: id, source: .conference(series: "AI/x", edition: id, round: "#1"), name: id.uppercased(), year: 2027,
            roundLabel: nil, abstractDate: abstract, paperDate: paper, state: .scheduled, timeZone: "AoE")
    }

    func plan(
        _ rows: [DeadlineRow] = [], papers: [Paper] = [], catalog: ConferenceCatalog = .empty,
        settings: AppSettings? = nil, calendar: Calendar = .gregorianLocal
    ) -> [PlannedReminder] {
        let work = papers.map { ($0, PaperDeadlines.resolve($0, catalog: catalog, now: now)) }
        return ReminderPlanner.plan(
            deadlines: DeadlineRows.followed(papers: work, starred: rows, now: now), papers: papers,
            settings: settings ?? self.settings, now: now, calendar: calendar)
    }

    @Test func nothingWhileNotificationsAreOff() {
        #expect(plan([row("a", paper: date("2026-11-01 12:00"))], settings: AppSettings()).isEmpty)
    }

    @Test func remindsAtEachLeadTimeStillAhead() {
        let deadline = date("2026-10-17 12:00")  // 5 days ahead: only the 3- and 1-day reminders remain
        let reminders = plan([row("a", paper: deadline)])
        #expect(reminders.map(\.fireDate) == [date("2026-10-14 12:00"), date("2026-10-16 12:00")])
        #expect(reminders[0].id == "a|paper|#1@\(Int(date("2026-10-14 12:00").timeIntervalSince1970))")
        #expect(reminders[0].destination == .deadline(.conference(series: "AI/x", edition: "a", round: "#1")))
    }

    @Test func abstractAndPaperBothCount() {
        let reminders = plan([row("a", paper: date("2026-11-16 12:00"), abstract: date("2026-11-10 12:00"))])
        #expect(reminders.count == 6)
        #expect(Set(reminders.map(\.id)).count == 6)
    }

    @Test func aPaperSpeaksForItsRound() throws {
        // A starred CVPR and a paper aiming at it: one reminder per date, which opens the paper.
        let star = DeadlineRow(
            id: "cvpr27|#1", source: .conference(series: "AI/cvpr", edition: "cvpr27", round: "#1"), name: "CVPR",
            year: 2027, roundLabel: nil, abstractDate: nil, paperDate: cvprPaper.date, state: .scheduled,
            timeZone: "UTC-12")
        let paper = Paper(title: "P", target: Paper.Target(series: "AI/cvpr", year: 2027), stage: .writing)
        let reminders = plan([star], papers: [paper], catalog: catalog(decision: cvprDecision))
        #expect(reminders.count == 3)
        #expect(reminders.allSatisfy { $0.destination == .paper(paper.id) })
        // Submitted, it is done, and the star does not remind of it either; the notification is
        // never reminded of.
        var submitted = paper
        submitted.stage = .submitted
        #expect(plan([star], papers: [submitted], catalog: catalog(decision: cvprDecision)).isEmpty)
        // A decided paper's camera-ready still is.
        var decided = paper
        decided.stage = .decided
        decided.deadlines = [CustomDeadline(title: "Camera-ready", date: date("2027-03-01 12:00"))]
        let cameraReady = plan(papers: [decided], catalog: catalog(decision: cvprDecision))
        #expect(cameraReady.count == 3)
        if case let .deadline(followed, _) = try #require(cameraReady.first?.content) {
            #expect(followed.title == "P" && followed.paperID == decided.id)
        }
    }

    @Test func blockRemindersAtNineOnTheLastDay() throws {
        let block = TimeBlock(kind: .writing, start: day(10, 10), end: day(10, 20))
        let done = TimeBlock(kind: .experiments, start: day(10, 1), end: day(10, 25), isDone: true)
        let milestone = Milestone(title: "Draft", day: day(10, 22))
        let paper = Paper(
            title: "P", blocks: [block, done],
            milestones: [milestone, Milestone(title: "Sent", day: day(10, 15), isDone: true)])
        let reminders = plan(papers: [paper], calendar: amsterdam)
        let reminder = try #require(reminders.first)
        #expect(reminders.count == 2)
        #expect(reminder.fireDate == date("2026-10-20 09:00", amsterdam.timeZone))
        #expect(reminder.destination == .paper(paper.id))
        #expect(reminders[1].content == .milestoneDue(paperTitle: "P", milestone: milestone))
        #expect(reminders[1].fireDate == date("2026-10-22 09:00", amsterdam.timeZone))
        var off = settings
        off.blockReminders = false
        #expect(plan(papers: [paper], settings: off, calendar: amsterdam).isEmpty)
    }

    @Test func daysBeforeAreDaysOnTheCalendar() {
        // Amsterdam's clocks go back on 25 October: a week before 23:59 on the 30th is 23:59 on the 23rd.
        var settings = settings
        settings.reminderDays = [7]
        let reminders = plan(
            [row("a", paper: date("2026-10-30 23:59", amsterdam.timeZone))], settings: settings, calendar: amsterdam)
        #expect(reminders.map(\.fireDate) == [date("2026-10-23 23:59", amsterdam.timeZone)])
    }

    @Test func keepsOnlyTheNextSixty() {
        let rows = (1...40).map { row("r\($0)", paper: now.addingTimeInterval(Double($0) * 10 * 86_400)) }
        let reminders = plan(rows)
        #expect(reminders.count == 60)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
    }
}

@Suite struct ChangeDetectorTests {
    func item(_ raw: String, kind: DeadlineKind = .paper) -> DeadlineItem {
        DeadlineItem(
            seriesKey: "AI/iclr", editionID: "iclr27", title: "ICLR", year: 2027, kind: kind, roundID: "#1",
            roundLabel: nil, value: DeadlineValue(raw: raw, date: nil), timeZone: "AoE")
    }

    @Test func firstSightingIsOnlyRecorded() {
        let result = ChangeDetector.detect(items: [item("2026-09-25 23:59:59")], lastSeen: [:])
        #expect(result.changes.isEmpty)
        #expect(result.lastSeen == ["iclr27|paper|#1": "2026-09-25 23:59:59"])
    }

    @Test func changedTextIsReportedAndStaleEntriesAreDropped() throws {
        let lastSeen = ["iclr27|paper|#1": "2026-09-25 23:59:59", "gone|paper|#1": "2026-01-01 23:59:59"]
        let result = ChangeDetector.detect(items: [item("2026-10-01 23:59:59")], lastSeen: lastSeen)
        let change = try #require(result.changes.first)
        #expect(change.item.editionTitle == "ICLR 2027")
        #expect(change.compact.old == "09-25")
        #expect(change.compact.new == "10-01")
        #expect(result.lastSeen.keys.sorted() == ["iclr27|paper|#1"])
    }

    @Test func compactForms() {
        #expect(ChangeDetector.compact("TBD", "2026-10-01 23:59:59") == ("TBD", "10-01"))
        #expect(ChangeDetector.compact("2026-10-01 23:59:59", "2026-10-01 12:00:00") == ("10-01 23:59", "10-01 12:00"))
        #expect(ChangeDetector.compact("2026-12-30 23:59:59", "2027-01-05 23:59:59") == ("2026-12-30", "2027-01-05"))
    }
}
