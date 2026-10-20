import DrBarKit
import Foundation
import Testing

@testable import CCFDDLKit

/// 2026-10-12 12:00 UTC, the "today" of these tests.
let referenceNow = Date(timeIntervalSince1970: 1_791_806_400)

func utc(_ text: String) -> Date {
    DeadlineParser.date(from: text, in: .gmt)!
}

func sampleYAML() throws -> String {
    let url = try #require(Bundle.module.url(forResource: "sample", withExtension: "yml", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

func sampleCatalog() throws -> ConferenceCatalog {
    try DeadlineParser.parse(yaml: sampleYAML(), now: referenceNow).catalog
}

@Suite struct DeadlineParserTests {
    @Test func referenceDateIsWhatTheTestsAssume() {
        #expect(utc("2026-10-12 12:00:00") == referenceNow)
    }

    @Test func parsesDateInTimeZone() throws {
        let aoe = try #require(DeadlineTimeZone.ccf("AoE"))
        let date = try #require(DeadlineParser.date(from: "2026-11-16 23:59:59", in: aoe))
        #expect(date == utc("2026-11-17 11:59:59"))
    }

    @Test func dateWithoutTimeMeansEndOfDay() {
        #expect(DeadlineParser.date(from: "2026-12-20", in: .gmt) == utc("2026-12-20 23:59:59"))
    }

    @Test(arguments: [
        "TBD", "tbd", "", "  ", "2026-02-30 23:59:59", "2026-13-01 10:00:00", "2026-11-16 25:00:00", "Nov 16",
    ])
    func rejectsTextThatIsNotADate(_ text: String) {
        #expect(DeadlineParser.date(from: text, in: .gmt) == nil)
    }

    @Test func pacificTimeFollowsDaylightSaving() throws {
        let pt = try #require(DeadlineTimeZone.ccf("PT"))
        // 1 August is daylight time (UTC-7); 1 November 17:00 is after the switch back (UTC-8).
        #expect(DeadlineParser.date(from: "2026-08-01 17:00:00", in: pt) == utc("2026-08-02 00:00:00"))
        #expect(DeadlineParser.date(from: "2026-11-01 17:00:00", in: pt) == utc("2026-11-02 01:00:00"))
    }

    @Test func malformedEntriesAreSkippedOneByOne() throws {
        let parsed = try DeadlineParser.parse(yaml: sampleYAML(), now: referenceNow)
        // The series without a title is skipped; the others survive. OddConf's time zone cannot be
        // read, so none of its dates count.
        #expect(parsed.catalog.series.count == 7 && parsed.seriesCount == 6)
        let keys = parsed.catalog.series.map(\.id)
        #expect(!keys.contains("AI/broken"))
        let half = try #require(parsed.catalog.series(withKey: "NW/half"))
        #expect(half.editions.map(\.id) == ["half27"])
    }

    @Test func readsTheRanksOfEveryList() throws {
        let catalog = try sampleCatalog()
        let cvpr = try #require(catalog.series(withKey: "AI/cvpr"))
        #expect(cvpr.ccfRank == "A" && cvpr.coreRank == "A*" && cvpr.thcplRank == "A")
        #expect(cvpr.displayCoreRank == "A*")
        #expect(cvpr.dblpURL?.absoluteString == "https://dblp.org/db/conf/cvpr/")
        // A series that only CCF ranks has no CORE or TH-CPL rank, and N is shown as none.
        let odd = try #require(catalog.series.first { $0.title == "OddConf" })
        #expect(odd.ccfRank == "N" && odd.coreRank == nil && odd.thcplRank == nil)
        #expect(odd.displayRank == nil)
    }

    @Test func wholeFileThatIsNotAListThrows() {
        #expect(throws: (any Error).self) {
            try DeadlineParser.parse(yaml: "<html>Service unavailable</html>", now: referenceNow)
        }
    }

    @Test func oldEditionsAreDroppedButRememberedAsPrevious() throws {
        let cvpr = try #require(try sampleCatalog().series(withKey: "AI/cvpr"))
        #expect(cvpr.editions.map(\.year) == [2026, 2027, 2028])
        #expect(
            cvpr.editions[0].previous == PreviousEdition(year: 2023, paperDeadline: "2022-11-11 23:59:59"))
        #expect(cvpr.editions[1].previous?.year == 2026)
        #expect(cvpr.editions[1].previous?.paperDeadline == "2025-11-13 23:59:59")
    }

    @Test func roundIDsComeFromCommentsAndStayUnique() throws {
        let sigmod = try #require(try sampleCatalog().series(withKey: "DB/sigmod"))
        let rounds = sigmod.editions[0].rounds
        #expect(rounds.map(\.id) == ["round 3", "round 4", "Extended round #3", "Extended round #4", "#5"])
        #expect(rounds.map { $0.label(roundCount: rounds.count) } == ["round 3", "round 4", "#3", "#4", "#5"])
    }

    @Test func quotedYearAndUnquotedTimestampAreRead() throws {
        let catalog = try sampleCatalog()
        #expect(catalog.series(withKey: "DB/vldb")?.editions.first?.year == 2027)
        let half = try #require(catalog.series(withKey: "NW/half")?.editions.first)
        #expect(half.rounds[1].paper?.date == utc("2027-01-20 23:59:59"))
    }

    @Test func unknownTimeZoneKeepsTheTextButNoDate() throws {
        let odd = try #require(try sampleCatalog().series(withKey: "MX/oddconf"))
        let round = try #require(odd.editions.first?.rounds.first)
        #expect(round.paper?.raw == "2026-12-01 23:59:59")
        #expect(round.paper?.date == nil)
        #expect(odd.editions.first?.timeZone == "CET")
    }

    @Test func snapshotDateIsReadFromTheHeader() throws {
        let data = Data(try sampleYAML().utf8)
        #expect(CCFDDLClient.snapshotDate(in: data) == utc("2026-10-12 00:00:00"))
        #expect(CCFDDLClient.snapshotDate(in: Data("- title: X".utf8)) == nil)
    }
}

@Suite struct AcceptanceTests {
    static let yaml = """
        - title: CVPR
          accept_rates:
          - year: 2026
            submitted: 16092
            accepted: 4089
            rate: 0.2541
          - year: '2025'
            submitted: 13008
            accepted: 2878
          - year: 2024
            rate: 1.7
          conference_key: AI/cvpr
        - title: sigmod
          accept_rates:
          - year: 2025
            rate: 0.21
        - title: Nowhere
          conference_key: AI/nowhere
        """

    @Test func ratesAreReadYearByYear() throws {
        let rates = try DeadlineParser.parseAcceptance(yaml: Data(Self.yaml.utf8))
        // A conference without any year says nothing; a rate above 1 is not one.
        #expect(rates.map(\.title) == ["CVPR", "sigmod"])
        #expect(rates[0].seriesKey == "AI/cvpr" && rates[1].seriesKey == nil)
        #expect(rates[0].years.map(\.year) == [2026, 2025])
        // Without a rate, the counts give it.
        #expect(rates[0].years[1].rate == 2878.0 / 13008 && rates[0].years[1].accepted == 2878)
        // Conference data is not taken for rates.
        let conferences = try DeadlineParser.parseAcceptance(yaml: Data(sampleYAML().utf8))
        #expect(conferences.isEmpty)
    }

    @Test func ratesJoinTheirSeriesByKeyOrByAUniqueTitle() throws {
        let rates = try DeadlineParser.parseAcceptance(yaml: Data(Self.yaml.utf8))
        let catalog = try sampleCatalog().withAcceptance(rates)
        let cvpr = try #require(catalog.series(withKey: "AI/cvpr"))
        #expect(cvpr.acceptance.map(\.year) == [2025, 2026] && cvpr.latestAcceptance?.rate == 0.2541)
        #expect(catalog.series(withKey: "DB/sigmod")?.acceptance.map(\.rate) == [0.21])
        #expect(catalog.series(withKey: "AI/colt")?.acceptance.isEmpty == true)
        // A title that two series share matches neither.
        var twice = try sampleCatalog()
        var copy = try #require(twice.series(withKey: "DB/sigmod"))
        copy.id = "DB/sigmod-2"
        twice.series.append(copy)
        let shared = twice.withAcceptance(rates).series.filter { $0.title == "SIGMOD" }
        #expect(shared.count == 2 && shared.allSatisfy { $0.acceptance.isEmpty })
    }
}

@Suite struct DeadlineRowsTests {
    /// The rows of what `following` covers, or else of every conference.
    func rows(following: Following? = nil, now: Date = referenceNow, recentSince: Date? = nil) throws -> [DeadlineRow] {
        let catalog = try sampleCatalog()
        return DeadlineRows.build(
            catalog: catalog, following: following ?? Following(starredSeries: Set(catalog.series.map(\.id))), now: now,
            recentSince: recentSince)
    }

    @Test func allShowsFutureDeadlinesInOrderThenNotAnnouncedThenUnreadable() throws {
        let titles = try rows().map {
            [$0.title, $0.roundLabel].compactMap { $0 }.joined(separator: " ")
        }
        #expect(
            titles == [
                "SIGMOD 2027 round 4",  // 17 Oct
                "VLDB 2027 Autumn",  // 1 Nov (abstract 25 Oct)
                "CVPR 2027",  // 16 Nov
                "SIGMOD 2027 #3",  // 1 Dec
                "EdgeConf 2027 Date only",  // 20 Dec
                "EdgeConf 2027 Abstract only",  // 24 Dec, abstract only
                "HalfBroken 2027 #1",  // 10 Jan
                "SIGMOD 2027 #4",  // 15 Jan
                "HalfBroken 2027 #2",  // 20 Jan
                "SIGMOD 2027 #5",
                "COLT 2027",  // TBD
                "EdgeConf 2027 Impossible",  // unreadable
                "OddConf 2027",  // unknown time zone
            ])
    }

    @Test func statesAndDates() throws {
        let all = try rows()
        let cvpr = try #require(all.first { $0.title == "CVPR 2027" })
        #expect(cvpr.state == .scheduled)
        #expect(cvpr.paperDate == utc("2026-11-17 11:59:59"))
        #expect(cvpr.abstractDate == utc("2026-11-11 11:59:59"))
        #expect(all.first { $0.title == "COLT 2027" }?.state == .notAnnounced)
        #expect(all.first { $0.title == "OddConf 2027" }?.state == .unreadable)
        let abstractOnly = try #require(all.first { $0.roundLabel == "Abstract only" })
        #expect(abstractOnly.paperDate == nil)
        #expect(abstractOnly.endDate == abstractOnly.abstractDate)
    }

    @Test func followingShowsStarredSeriesAndTargetedEditions() throws {
        let following = Following(starredSeries: ["AI/cvpr"], targetedEditions: [.init(series: "AI/colt", year: 2027)])
        #expect(try rows(following: following).map(\.title) == ["CVPR 2027", "COLT 2027"])
    }

    @Test func notAnnouncedIsHiddenWhileTheSeriesHasADatedDeadline() throws {
        #expect(!(try rows().map(\.title).contains("CVPR 2028")))
        let later = try rows(now: utc("2026-11-20 00:00:00"))
        #expect(!later.map(\.title).contains("CVPR 2027"))
        #expect(later.first { $0.title == "CVPR 2028" }?.state == .notAnnounced)
    }

    @Test func recentlyPassedDeadlinesStayWhileTheAxisShowsThem() throws {
        let now = utc("2026-11-20 00:00:00")
        let passed = try rows(
            following: Following(starredSeries: ["AI/cvpr"]), now: now,
            recentSince: now.addingTimeInterval(-7 * 86_400))
        #expect(passed.map(\.title) == ["CVPR 2027", "CVPR 2028"])
        #expect(passed.last?.state == .notAnnounced)
        #expect(DeadlineRows.upcoming(DeadlineRows.followed(papers: [], starred: passed, now: now), limit: 3).isEmpty)
    }

    @Test func filtersByCategoryRankAndSearch() throws {
        let series = try sampleCatalog().series
        func keys(_ filter: DeadlineFilter) -> Set<String> {
            Set(series.filter(filter.matches).map(\.id))
        }
        #expect(keys(DeadlineFilter(scope: .all, categories: ["DB"])) == ["DB/sigmod", "DB/vldb"])
        #expect(keys(DeadlineFilter(scope: .all, ranks: ["B"])) == ["AI/colt", "NW/half"])
        #expect(keys(DeadlineFilter(scope: .all, search: "pattern recognition")) == ["AI/cvpr"])
    }

    @Test func menuBarPicksTheNearestAbstractOrPaperDeadline() throws {
        let following = Following(starredSeries: ["AI/cvpr", "DB/vldb"])
        let followed = DeadlineRows.followed(
            papers: [], starred: try rows(following: following), now: referenceNow)
        let next = try #require(DeadlineRows.upcoming(followed, limit: 1).first)
        #expect(next.name == "VLDB")
        #expect(next.deadline.kind == .abstract)
        #expect(next.date == DeadlineParser.date(from: "2026-10-25 17:00:00", in: DeadlineTimeZone.ccf("PT")!))
        // The next of each: CVPR's abstract, not VLDB's paper deadline after its abstract.
        #expect(DeadlineRows.upcoming(followed, limit: 2).map(\.name) == ["VLDB", "CVPR"])
    }

    @Test func aPaperSpeaksForTheStarredRoundItAimsAt() throws {
        let catalog = try sampleCatalog()
        let starred = try rows(following: Following(starredSeries: ["AI/cvpr"]))
        var paper = Paper(title: "P", target: Paper.Target(series: "AI/cvpr", year: 2027), stage: .writing)
        func followed(_ papers: [Paper]) -> [FollowedDeadline] {
            DeadlineRows.followed(
                papers: papers.map { ($0, PaperDeadlines.resolve($0, catalog: catalog, now: referenceNow)) },
                starred: starred, now: referenceNow)
        }
        // Once each, opening the paper: the abstract, the paper, the rebuttal and the notification.
        let mine = followed([paper])
        #expect(
            mine.map(\.id) == ["cvpr27|abstract|#1", "cvpr27|paper|#1", "cvpr27|rebuttal|#1", "cvpr27|decision|#1"])
        #expect(mine.allSatisfy { $0.destination == .paper(paper.id) && $0.paperID == paper.id && $0.name == "CVPR" })
        // Two papers on one round: the conference's details, which neither is.
        let other = Paper(title: "Q", target: paper.target, stage: .writing)
        #expect(
            followed([paper, other]).first?.destination
                == .deadline(.conference(series: "AI/cvpr", edition: "cvpr27", round: "#1")))
        // Shared, it is the round's: a deadline of one of the papers does not hide it from the menu bar.
        var early = paper
        early.deadlines = [CustomDeadline(title: "Draft", date: utc("2026-11-01 12:00:00"))]
        #expect(followed([early, other]).first { $0.deadline.kind != nil }?.owner == "cvpr27|#1")
        #expect(
            DeadlineRows.upcoming(followed([early, other]), limit: 2).map(\.id) == [
                early.deadlines[0].id.uuidString, "cvpr27|abstract|#1",
            ])
        // Submitted, the star no longer reminds of what the paper has done.
        paper.stage = .submitted
        #expect(followed([paper]).map(\.id) == ["cvpr27|rebuttal|#1", "cvpr27|decision|#1"])
    }

    @Test func aDeadlineCountsDownFromWhenItsWorkStarted() throws {
        let catalog = try sampleCatalog()
        let starred = try rows(following: Following(starredSeries: ["AI/cvpr", "DB/vldb"]))
        func followed(_ papers: [Paper]) -> [FollowedDeadline] {
            DeadlineRows.followed(
                papers: papers.map { ($0, PaperDeadlines.resolve($0, catalog: catalog, now: referenceNow)) },
                starred: starred, now: referenceNow)
        }
        let added = utc("2026-09-01 08:00:00")
        let cvpr = Paper.Target(series: "AI/cvpr", year: 2027)
        var paper = Paper(title: "P", target: cvpr, stage: .writing, createdAt: added)
        func start(_ papers: [Paper]) -> Date? {
            followed(papers).first { $0.name == "CVPR" }?.start
        }
        // From when it was added, then from the first day of its plan.
        #expect(start([paper]) == added)
        func day(_ month: Int, _ day: Int) -> Day { Day(year: 2026, month: month, day: day) }
        paper.blocks = [
            TimeBlock(kind: .writing, start: day(10, 20), end: day(11, 10)),
            TimeBlock(kind: .experiments, start: day(10, 1), end: day(10, 19)),
        ]
        #expect(start([paper]) == day(10, 1).startDate())
        // Shared, from the earliest of its papers; a conference followed on its own has no start.
        let earlier = utc("2026-08-01 00:00:00")
        let other = Paper(title: "Q", target: cvpr, stage: .writing, createdAt: earlier)
        #expect(start([paper, other]) == earlier)
        #expect(followed([]).allSatisfy { $0.start == nil })

        // A whole round until the work starts, half of it halfway to the deadline, none at it.
        var deadline = try #require(followed([paper]).first)
        deadline.date = utc("2026-11-11 00:00:00")
        deadline.start = utc("2026-10-12 00:00:00")
        let month: TimeInterval = 30 * 86_400
        #expect(deadline.shareLeft(at: utc("2026-10-01 00:00:00"), fallback: month) == 1)
        #expect(deadline.shareLeft(at: utc("2026-10-27 00:00:00"), fallback: month) == 0.5)
        #expect(deadline.shareLeft(at: deadline.date, fallback: month) == 0)
        // Without a start before the deadline, the fallback is its round.
        deadline.start = nil
        #expect(deadline.shareLeft(at: utc("2026-10-27 00:00:00"), fallback: 2 * month) == 0.25)
        deadline.start = utc("2026-11-12 00:00:00")
        #expect(deadline.shareLeft(at: utc("2026-10-27 00:00:00"), fallback: 2 * month) == 0.25)
    }
}

@Suite struct PaperDeadlinesTests {
    let catalog: ConferenceCatalog
    let amsterdam = Calendar.gregorian(in: TimeZone(identifier: "Europe/Amsterdam")!)
    let cvpr = Paper.Target(series: "AI/cvpr", year: 2027)

    init() throws {
        catalog = try sampleCatalog()
    }

    func resolve(_ paper: Paper, now: Date = referenceNow, in catalog: ConferenceCatalog? = nil) -> PaperDeadlines {
        PaperDeadlines.resolve(paper, catalog: catalog ?? self.catalog, now: now, calendar: amsterdam)
    }

    /// A supplementary a week after CVPR's paper deadline, in the conference's own time zone.
    let supplementary = CustomDeadline(title: "Supplementary", date: utc("2026-11-24 11:59:59"), timeZone: "UTC-12")

    @Test func picksTheNextRoundUnlessOneIsChosen() {
        let sigmod = Paper.Target(series: "DB/sigmod", year: 2027)
        #expect(resolve(Paper(title: "P", target: sigmod)).conference?.roundLabel == "round 4")
        var chosen = sigmod
        chosen.round = "#5"
        #expect(resolve(Paper(title: "P", target: chosen)).main?.value.raw == "2027-02-15 23:59:59")
        #expect(
            resolve(Paper(title: "P", target: sigmod), now: utc("2027-06-01 00:00:00")).conference?.roundLabel == "#5")
    }

    @Test func listsTheRoundsDatesAndItsOwnInOrder() {
        let deadlines = resolve(Paper(title: "P", target: cvpr, deadlines: [supplementary], stage: .writing))
        #expect(
            deadlines.all.map(\.id) == [
                "cvpr27|abstract|#1", "cvpr27|paper|#1", supplementary.id.uuidString, "cvpr27|rebuttal|#1",
                "cvpr27|decision|#1",
            ])
        #expect(deadlines.main?.kind == .paper && deadlines.flag?.kind == .paper)
        #expect(deadlines.next(after: referenceNow)?.kind == .abstract)
        #expect(deadlines.title == "CVPR 2027" && !deadlines.canChooseMain)
        #expect(deadlines.all.map(\.completion) == [.tick, .submission, .tick, .tick, .decision])
    }

    @Test func theFlagFollowsTheStage() {
        var paper = Paper(title: "P", target: cvpr, deadlines: [supplementary], stage: .writing)
        #expect(resolve(paper).flag?.date == utc("2026-11-17 11:59:59"))
        // Submitted, the paper deadline and the abstract are done, and the flag moves on: to the
        // supplementary, then once that has passed, the rebuttal, then the notification.
        paper.stage = .submitted
        let submitted = resolve(paper, now: utc("2026-11-20 00:00:00"))
        #expect(submitted.all.filter(\.isDone).compactMap(\.kind) == [.abstract, .paper])
        // Marking the paper not submitted takes the main deadline back, until it is decided.
        #expect(submitted.main?.isDoneByStage == false && submitted.all.first?.isDoneByStage == true)
        paper.stage = .decided
        #expect(resolve(paper, now: utc("2026-11-20 00:00:00")).main?.isDoneByStage == true)
        paper.stage = .submitted
        #expect(submitted.flag?.title == "Supplementary")
        #expect(resolve(paper, now: utc("2026-12-01 00:00:00")).flag?.kind == .rebuttal)
        #expect(resolve(paper, now: utc("2027-02-10 00:00:00")).flag?.kind == .decision)
        #expect(resolve(paper, now: utc("2027-03-01 00:00:00")).flag == nil)
    }

    @Test func aDecidedPaperKeepsItsCameraReady() {
        let cameraReady = CustomDeadline(title: "Camera-ready", date: utc("2027-04-01 11:59:59"))
        var sent = supplementary
        sent.isDone = true
        let paper = Paper(title: "P", target: cvpr, deadlines: [sent, cameraReady], stage: .decided)
        let deadlines = resolve(paper, now: utc("2027-03-01 00:00:00"))
        #expect(deadlines.all.filter { !$0.isDone }.map(\.title) == ["Camera-ready"])
        #expect(deadlines.flag?.title == "Camera-ready")
        #expect(deadlines.cutoffs == Cutoffs(days: [Day(year: 2027, month: 4, day: 1)], closesThePlan: false))
    }

    @Test func aTickedAbstractIsDoneAndNextMovesOn() {
        var paper = Paper(title: "P", target: cvpr, stage: .writing)
        paper.doneDeadlines = ["cvpr27|abstract|#1"]
        let deadlines = resolve(paper)
        #expect(deadlines.all.first?.isDone == true && deadlines.all.first?.isDoneByStage == false)
        #expect(deadlines.next(after: referenceNow)?.kind == .paper)
    }

    @Test func ticksBelongToTheirRound() {
        var paper = Paper(title: "P", target: Paper.Target(series: "DB/sigmod", year: 2027))
        paper.doneDeadlines = ["sigmod27|abstract|round 4"]
        #expect(resolve(paper).all.first { $0.kind == .abstract }?.isDone == true)
        // Once that round has passed, the next round has nothing ticked.
        #expect(resolve(paper, now: utc("2026-10-20 00:00:00")).all.allSatisfy { !$0.isDone })
    }

    @Test func anItemMovesOnWhenItsMainOneIsTicked() {
        let letters = CustomDeadline(title: "Letters", date: utc("2026-11-01 12:00:00"))
        var application = CustomDeadline(title: "Application", date: utc("2026-11-15 12:00:00"))
        let interview = CustomDeadline(title: "Interview", date: utc("2027-01-10 12:00:00"))
        var item = Paper(
            title: "Fellowship", deadlines: [letters, application, interview], mainDeadline: application.id,
            groupID: UUID())
        var deadlines = resolve(item)
        #expect(deadlines.flag?.title == "Application" && deadlines.next(after: referenceNow)?.title == "Letters")
        #expect(
            deadlines.cutoffs
                == Cutoffs(
                    days: [Day(year: 2026, month: 11, day: 15), Day(year: 2027, month: 1, day: 10)], closesThePlan: true
                ))
        #expect(deadlines.canChooseMain && deadlines.all.allSatisfy { $0.completion == .tick })
        application.isDone = true
        item.deadlines[1] = application
        deadlines = resolve(item)
        #expect(deadlines.flag?.title == "Interview")
        item.stage = .decided
        #expect(resolve(item).all.allSatisfy(\.isDone) && resolve(item).flag == nil)
    }

    @Test func aRoundWithOnlyItsAbstractIsNotAnnounced() {
        var target = Paper.Target(series: "SE/edge", year: 2027)
        target.round = "Abstract only"
        let overview = PaperOverview(paper: Paper(title: "P", target: target), catalog: catalog, now: referenceNow)
        #expect(overview.deadlineNotAnnounced && overview.cutoffs == .none && overview.planningDeadline == nil)
        #expect(overview.deadlines.next(after: referenceNow)?.kind == .abstract)
    }

    @Test func anEditionMissingFromTheCatalog() {
        let paper = Paper(
            title: "P", target: Paper.Target(series: "AI/gone", year: 2027), deadlines: [supplementary],
            mainDeadline: supplementary.id)
        let overview = PaperOverview(paper: paper, catalog: catalog, now: referenceNow)
        #expect(overview.deadlines.main == nil && overview.flag == nil && !overview.deadlineNotAnnounced)
        #expect(overview.deadlines.all.map(\.title) == ["Supplementary"])
    }

    @Test func notAnnouncedTarget() {
        let paper = Paper(title: "P", target: Paper.Target(series: "AI/colt", year: 2027))
        let overview = PaperOverview(paper: paper, catalog: catalog, now: referenceNow)
        #expect(overview.deadlineNotAnnounced)
        #expect(overview.flag == nil)
    }

    @Test func conflictsAfterSubmissionOnlyAcrossTheRebuttal() {
        let late = TimeBlock(
            kind: .writing, start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 30))
        var paper = Paper(title: "P", target: cvpr, stage: .writing, blocks: [late])
        #expect(
            PaperOverview(paper: paper, catalog: catalog, now: referenceNow, calendar: amsterdam).status == .conflict)
        // Work for a supplementary due after the paper deadline is not late.
        paper.blocks = [
            TimeBlock(
                kind: .custom, customName: "Video", start: Day(year: 2026, month: 11, day: 18),
                end: Day(year: 2026, month: 11, day: 24))
        ]
        paper.deadlines = [supplementary]
        #expect(
            PaperOverview(paper: paper, catalog: catalog, now: referenceNow, calendar: amsterdam).status == .onTrack)
        paper.stage = .submitted
        paper.blocks = [late]
        paper.deadlines = []
        #expect(
            PaperOverview(paper: paper, catalog: catalog, now: referenceNow, calendar: amsterdam).status == .onTrack)
        paper.blocks = [
            TimeBlock(
                kind: .custom, customName: "Rebuttal", start: Day(year: 2027, month: 1, day: 25),
                end: Day(year: 2027, month: 2, day: 5))
        ]
        #expect(
            PaperOverview(paper: paper, catalog: catalog, now: referenceNow, calendar: amsterdam).status == .conflict)
    }

    @Test func submittingFixesTheNearestRound() {
        for now in [utc("2026-10-12 00:00:00"), utc("2026-10-20 00:00:00")] {
            var data = UserData(papers: [
                Paper(title: "P", target: Paper.Target(series: "DB/sigmod", year: 2027), stage: .writing)
            ])
            data.setStage(.submitted, of: data.papers[0].id, catalog: catalog, now: now)
            #expect(data.papers[0].target?.round == "round 4")
        }
        // An edition of one round has it fixed too, for when ccfddl adds another.
        var data = UserData(papers: [Paper(title: "P", target: cvpr, stage: .writing)])
        data.setStage(.submitted, of: data.papers[0].id, catalog: catalog, now: referenceNow)
        #expect(data.papers[0].target?.round == "#1")
        // The round is fixed even while the other rounds are not announced.
        data = UserData(papers: [Paper(title: "P", target: Paper.Target(series: "SE/edge", year: 2027))])
        data.setStage(.submitted, of: data.papers[0].id, catalog: catalog, now: utc("2026-12-20 12:00:00"))
        #expect(data.papers[0].target?.round == "Date only")
    }

    @Test func goingBackLetsGoOfTheRound() {
        // Passed or still ahead, the paper follows the round to come.
        for round in ["round 4", "#5"] {
            let target = Paper.Target(series: "DB/sigmod", year: 2027, round: round)
            var data = UserData(papers: [Paper(title: "P", target: target, stage: .submitted)])
            data.setStage(.writing, of: data.papers[0].id, catalog: catalog, now: utc("2026-11-01 00:00:00"))
            #expect(data.papers[0].target?.round == nil)
        }
    }

    @Test func aRoundAddedLaterDoesNotTakeTheSubmittedOnesPlace() throws {
        var data = UserData(papers: [Paper(title: "P", target: cvpr, stage: .writing)])
        data.setStage(.submitted, of: data.papers[0].id, catalog: catalog, now: utc("2026-11-16 12:00:00"))
        // ccfddl adds a later round to the edition.
        var later = catalog
        let s = try #require(later.series.firstIndex { $0.id == "AI/cvpr" })
        let e = try #require(later.series[s].editions.firstIndex { $0.year == 2027 })
        let winter = DeadlineValue(raw: "2027-03-13 23:59:59", date: utc("2027-03-14 11:59:59"))
        later.series[s].editions[e].rounds.append(
            ConferenceRound(
                id: "#2", index: 1, comment: nil, abstract: nil, paper: winter, rebuttal: nil, decision: nil))
        let deadlines = resolve(data.papers[0], now: utc("2026-12-01 00:00:00"), in: later)
        #expect(deadlines.conference?.source == .conference(series: "AI/cvpr", edition: "cvpr27", round: "#1"))
        let pinned = data.pinSubmittedRounds(in: later, now: utc("2026-12-01 00:00:00"))
        #expect(!pinned)
    }

    @Test func aRejectedPaperPointedElsewhereFollowsTheRoundsToCome() {
        // As after a rejection: the conference changed, then back to Writing.
        var data = UserData(papers: [Paper(title: "P", target: cvpr, stage: .decided)])
        let id = data.papers[0].id
        let sigmod = Paper.Target(series: "DB/sigmod", year: 2027)
        data.setTarget(sigmod, of: id, catalog: catalog, now: referenceNow)
        #expect(data.papers[0].target == sigmod)
        let pinned = data.pinSubmittedRounds(in: catalog, now: referenceNow)
        #expect(!pinned)
        data.setStage(.writing, of: id, catalog: catalog, now: referenceNow)
        // Round 4 passes without it; it follows the next round.
        let deadlines = resolve(data.papers[0], now: utc("2026-10-20 00:00:00"))
        #expect(
            deadlines.conference?.source
                == .conference(series: "DB/sigmod", edition: "sigmod27", round: "Extended round #3"))
        #expect(deadlines.next(after: utc("2026-10-20 00:00:00"))?.kind == .paper)
    }

    @Test func aRoundStillToBeAnnouncedComesAfterThoseThatPassed() {
        let passed = DeadlineValue(raw: "2026-09-30 23:59:59", date: utc("2026-10-01 11:59:59"))
        let edition = ConferenceEdition(
            id: "acisp27", year: 2027, link: "", timeZone: "AoE", date: nil, place: nil,
            rounds: [
                ConferenceRound(
                    id: "Round 1", index: 0, comment: "Round 1", abstract: nil, paper: passed, rebuttal: nil,
                    decision: nil),
                ConferenceRound(
                    id: "Round 2", index: 1, comment: "Round 2", abstract: nil,
                    paper: DeadlineValue(raw: "TBD", date: nil), rebuttal: nil, decision: nil),
            ], previous: nil)
        let catalog = ConferenceCatalog(series: [
            ConferenceSeries(
                id: "SC/acisp", title: "ACISP", description: "", category: "SC", ccfRank: "C", editions: [edition])
        ])
        let now = utc("2026-10-17 00:00:00")
        #expect(edition.round(id: nil, now: utc("2026-09-01 00:00:00"))?.id == "Round 1")
        #expect(edition.round(id: nil, now: now)?.id == "Round 2")
        let paper = Paper(title: "P", target: Paper.Target(series: "SC/acisp", year: 2027), stage: .writing)
        let overview = PaperOverview(paper: paper, catalog: catalog, now: now)
        #expect(overview.deadlineNotAnnounced && overview.deadlines.conference?.roundLabel == "Round 2")
        // The Conferences page lists it as coming, not as passed.
        let choices = TargetChoices.build(
            catalog: catalog, starred: [], filter: DeadlineFilter(scope: .all), current: nil, now: now)
        #expect(choices.map(\.title) == ["ACISP 2027"])
        #expect(choices.first?.state == .notAnnounced && choices.first?.hasPassed == false)
        #expect(choices.first?.roundLabel == "Round 2")
    }

    @Test func olderSubmittedPapersGetTheirRoundOnce() {
        var data = UserData(papers: [
            Paper(title: "P", target: Paper.Target(series: "DB/sigmod", year: 2027), stage: .submitted)
        ])
        let pinned = data.pinSubmittedRounds(in: catalog, now: referenceNow)
        #expect(pinned && data.papers[0].target?.round == "round 4")
        let again = data.pinSubmittedRounds(in: catalog, now: utc("2027-01-10 00:00:00"))
        #expect(!again)
    }

    @Test func choosingAConferenceKeepsOwnDeadlinesAndForgetsWhatPassed() {
        let passed = CustomDeadline(title: "Workshop", date: utc("2026-09-01 12:00:00"))
        var paper = Paper(title: "P", target: cvpr, deadlines: [passed, supplementary], stage: .writing)
        paper.doneDeadlines = ["cvpr27|abstract|#1"]
        var data = UserData(papers: [paper])
        // Another round of the same edition keeps everything.
        data.setTarget(
            Paper.Target(series: "AI/cvpr", year: 2027, round: "#1"), of: paper.id, catalog: catalog, now: referenceNow)
        #expect(data.papers[0].deadlines.count == 2 && data.papers[0].doneDeadlines.count == 1)
        data.setTarget(Paper.Target(series: "DB/vldb", year: 2027), of: paper.id, catalog: catalog, now: referenceNow)
        #expect(data.papers[0].deadlines.map(\.title) == ["Supplementary"] && data.papers[0].doneDeadlines.isEmpty)
    }
}
