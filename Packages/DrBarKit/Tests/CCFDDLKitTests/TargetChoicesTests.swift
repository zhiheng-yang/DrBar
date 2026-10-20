import DrBarKit
import Foundation
import Testing

@Suite struct TargetChoicesTests {
    let catalog: ConferenceCatalog

    init() throws {
        catalog = try sampleCatalog()
    }

    func choices(_ filter: DeadlineFilter = .init(scope: .all), current: Paper.Target? = nil) -> [TargetChoice] {
        TargetChoices.build(catalog: catalog, starred: ["AI/cvpr"], filter: filter, current: current, now: referenceNow)
    }

    @Test func comingDeadlinesFirstThenWhatIsNotAnnounced() {
        // SIGMOD's next round, on 17 October, comes before VLDB's and CVPR's; past editions are
        // left out.
        #expect(
            choices().map(\.title) == [
                "SIGMOD 2027", "VLDB 2027", "CVPR 2027", "EdgeConf 2027", "HalfBroken 2027", "COLT 2027", "CVPR 2028",
                "OddConf 2027",
            ])
    }

    @Test func filtersByCategoryAndRank() {
        let filter = DeadlineFilter(scope: .all, categories: ["AI"], ranks: ["A"])
        #expect(choices(filter).map(\.title) == ["CVPR 2027", "CVPR 2028"])
        // Every list must let a conference through; one that a list does not rank counts as N.
        let core = DeadlineFilter(scope: .all, coreRanks: ["A*"], thcplRanks: ["B"])
        #expect(choices(core).map(\.title) == ["COLT 2027"])
        let unranked = DeadlineFilter(scope: .all, coreRanks: ["N"])
        #expect(choices(unranked).map(\.title).contains("OddConf 2027"))
        #expect(!choices(unranked).map(\.title).contains("CVPR 2027"))
    }

    @Test func aSearchLooksEverywhereAndBack() {
        let filter = DeadlineFilter(scope: .all, categories: ["DB"], ranks: ["C"], search: "cvpr")
        let found = choices(filter)
        // What is ahead first, then what has passed or is not announced.
        #expect(found.map(\.title) == ["CVPR 2027", "CVPR 2026", "CVPR 2028"])
        #expect(found.map(\.hasPassed) == [false, true, false])
    }

    @Test func starredOnesWhateverTheirCategoryAndRank() {
        let starred = DeadlineFilter(scope: .following, categories: ["DB"], ranks: ["C"])
        #expect(choices(starred).map(\.title) == ["CVPR 2027", "CVPR 2028"])
        #expect(choices(DeadlineFilter(scope: .following, search: "sigmod")).isEmpty)
        let vldb = Paper.Target(series: "DB/vldb", year: 2027)
        #expect(choices(DeadlineFilter(scope: .following), current: vldb).map(\.title).contains("VLDB 2027"))
    }

    @Test func aStarredConferenceWithNothingComingKeepsItsLastEdition() {
        let later = TargetChoices.build(
            catalog: catalog, starred: ["DB/sigmod"], filter: DeadlineFilter(scope: .following), current: nil,
            now: utc("2027-03-01 00:00:00"))
        #expect(later.map(\.title) == ["SIGMOD 2027"] && later.first?.hasPassed == true)
    }

    @Test func thePapersEditionIsAlwaysThere() {
        let filter = DeadlineFilter(scope: .all, categories: ["DB"])
        let current = Paper.Target(series: "AI/cvpr", year: 2026, round: "#1")
        #expect(choices(filter, current: current).map(\.title).contains("CVPR 2026"))
    }

    @Test func pastEditionsWhenAskedFor() {
        #expect(!choices().contains { $0.title == "CVPR 2026" })
        #expect(choices(DeadlineFilter(scope: .all, includesPassed: true)).contains { $0.title == "CVPR 2026" })
        let starred = choices(DeadlineFilter(scope: .following, includesPassed: true))
        #expect(starred.map(\.title) == ["CVPR 2027", "CVPR 2026", "CVPR 2028"])
        #expect(starred.map(\.hasPassed) == [false, true, false])
    }

    @Test func theRoundItsNoteTheAcceptanceRateAndLastYear() throws {
        let rates = [
            AcceptanceRates(
                seriesKey: "AI/cvpr", title: "CVPR",
                years: [AcceptanceRate(year: 2026, rate: 0.254), AcceptanceRate(year: 2025, rate: 0.221)])
        ]
        // After SIGMOD's fourth round, its first extended one is next.
        let later = TargetChoices.build(
            catalog: catalog.withAcceptance(rates), starred: [], filter: DeadlineFilter(scope: .all), current: nil,
            now: utc("2026-11-01 00:00:00"))
        let cvpr = try #require(later.first { $0.title == "CVPR 2027" })
        #expect(cvpr.acceptance == AcceptanceRate(year: 2026, rate: 0.254))
        #expect(cvpr.lastYear == Day(year: 2025, month: 11, day: 13))
        #expect(cvpr.roundLabel == nil && cvpr.note == nil)
        let sigmod = try #require(later.first { $0.title == "SIGMOD 2027" })
        #expect(sigmod.roundLabel == "#3" && sigmod.note == "Extended round" && sigmod.acceptance == nil)
        // The hardest first, the unknown last.
        #expect(cvpr.acceptanceOrder < sigmod.acceptanceOrder)
        #expect(choices().first { $0.title == "SIGMOD 2027" }?.note == nil)
    }

    @Test func eachChoiceKnowsWhatTheTableShows() throws {
        let all = choices()
        let cvpr = try #require(all.first { $0.title == "CVPR 2027" })
        #expect(cvpr.target == Paper.Target(series: "AI/cvpr", year: 2027))
        #expect(cvpr.detail == "IEEE/CVF Conference on Computer Vision and Pattern Recognition")
        #expect(cvpr.isStarred && cvpr.rank == "A" && cvpr.category == "AI")
        #expect(cvpr.coreRank == "A*" && cvpr.thcplRank == "A")
        #expect(cvpr.place?.hasPrefix("Seattle") == true && cvpr.meeting?.start == Day(year: 2027, month: 6, day: 20))
        // The unranked after C.
        let odd = try #require(all.first { $0.title == "OddConf 2027" })
        let edge = try #require(all.first { $0.title == "EdgeConf 2027" })
        #expect(odd.rank == nil && odd.coreRank == nil && odd.place == nil)
        #expect(odd.rankOrder > edge.rankOrder && edge.rank == "C")
        #expect(all.first { $0.title == "CVPR 2028" }?.deadline == nil)
        // What the date cells need: the abstract of the same round, the time zone, and whether
        // the deadline can be read.
        #expect(cvpr.name == "CVPR" && cvpr.timeZone == "UTC-12" && cvpr.state == .scheduled)
        #expect(cvpr.abstractDeadline == utc("2026-11-11 11:59:59"))
        #expect(edge.abstractDeadline == nil)
        #expect(odd.state == .unreadable)
        #expect(all.first { $0.title == "COLT 2027" }?.state == .notAnnounced)
    }
}
