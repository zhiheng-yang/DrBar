import DrBarKit
import Foundation
import Testing

@testable import CCFDDLKit

/// ccfddl names rounds by their comments and rewrites them, often in the commit that moves the
/// dates, and moves conferences to other keys; what was kept by the old names goes along to the
/// new ones.
@Suite struct CatalogRenamesTests {
    /// An edition of DFRWS EU 2027 with `timeline`, its rounds written as ccfddl writes them.
    func catalog(_ timeline: String, key: String = "SC/dfrws") throws -> ConferenceCatalog {
        let rounds = timeline.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        let yaml = """
            - title: DFRWS EU
              description: Digital Forensics Research Conference Europe
              sub: SC
              rank: { ccf: C }
              conference_key: \(key)
              confs:
              - year: 2027
                id: dfrws27
                link: https://dfrws.org/
                timeline:
            \(rounds)
                timezone: UTC
            """
        return try DeadlineParser.parse(yaml: yaml, now: referenceNow).catalog
    }

    let target = Paper.Target(series: "SC/dfrws", year: 2027)

    @Test func aCommentAddedWithNewDatesKeepsTheTicksAndTellsOfTheChange() throws {
        let before = try catalog(
            """
            - abstract_deadline: '2026-11-01 23:59:59'
              deadline: '2026-11-08 23:59:59'
            """)
        let after = try catalog(
            """
            - abstract_deadline: '2026-11-15 23:59:59'
              deadline: '2026-11-22 23:59:59'
              comment: Extended deadlines
            """)
        var paper = Paper(title: "P", target: target, stage: .writing)
        paper.doneDeadlines = ["dfrws27|abstract|#1"]
        let following = Following(targetedEditions: [Following.Edition(series: "SC/dfrws", year: 2027)])
        var data = UserData(
            papers: [paper],
            lastSeen: ChangeDetector.detect(items: before.items(following: following), lastSeen: [:]).lastSeen)

        let renames = before.renames(in: after)
        #expect(renames.round("#1", ofEdition: "dfrws27") == "Extended deadlines")
        let followed = data.follow(renames, in: after)
        #expect(followed)
        #expect(data.papers[0].doneDeadlines == ["dfrws27|abstract|Extended deadlines"])
        let abstract = PaperDeadlines.resolve(data.papers[0], catalog: after, now: referenceNow).all.first
        #expect(abstract?.kind == .abstract && abstract?.isDone == true)
        let changes = ChangeDetector.detect(items: after.items(following: following), lastSeen: data.lastSeen).changes
        #expect(changes.map(\.item.kind) == [.abstract, .paper])
        #expect(changes.first?.oldText == "2026-11-01 23:59:59")
    }

    @Test func aRenamedRoundKeepsTheSubmittedPaper() throws {
        let before = try catalog(
            """
            - deadline: '2026-09-01 23:59:59'
              comment: Round 1
            - deadline: '2026-12-01 23:59:59'
              comment: Round 2
            """)
        let after = try catalog(
            """
            - deadline: '2026-09-15 23:59:59'
              comment: Round 1 (extended)
            - deadline: '2026-12-01 23:59:59'
              comment: Round 2
            """)
        var round = target
        round.round = "Round 1"
        var data = UserData(papers: [Paper(title: "P", target: round, stage: .submitted)])
        data.follow(before.renames(in: after), in: after)
        #expect(data.papers[0].target?.round == "Round 1 (extended)")
        let deadlines = PaperDeadlines.resolve(data.papers[0], catalog: after, now: referenceNow)
        #expect(deadlines.main?.date == utc("2026-09-15 23:59:59") && deadlines.main?.isDone == true)
    }

    @Test func roundsAddedBeforeOrAfterLeaveTheOthersAlone() throws {
        // A track inserted before, found by its comment.
        var renames = try catalog("- deadline: '2026-12-01 23:59:59'\n  comment: Conference track")
            .renames(
                in: try catalog(
                    """
                    - deadline: '2026-11-01 23:59:59'
                      comment: Journal track
                    - deadline: '2026-12-01 23:59:59'
                      comment: Conference track
                    """))
        #expect(renames.isEmpty)
        // A round inserted before one without a comment, found by its date.
        renames = try catalog("- deadline: '2026-12-01 23:59:59'")
            .renames(in: try catalog("- deadline: '2026-11-01 23:59:59'\n- deadline: '2026-12-01 23:59:59'"))
        #expect(renames.round("#1", ofEdition: "dfrws27") == "#2")
        // A round inserted before one that is named, with its time written anew: found by its day.
        renames = try catalog("- deadline: '2026-10-01 23:59:00'")
            .renames(
                in: try catalog(
                    """
                    - deadline: '2026-09-01 23:59:59'
                      comment: Round 1
                    - deadline: '2026-10-01 23:59:59'
                      comment: Round 2
                    """))
        #expect(renames.round("#1", ofEdition: "dfrws27") == "Round 2")
        #expect(renames.deadlineID("dfrws27|paper|#1") == "dfrws27|paper|Round 2")
        #expect(renames.deadlineID("cvpr27|paper|#1") == "cvpr27|paper|#1")
        // Rounds added and the old one moved and named at once: nothing tells which it became.
        renames = try catalog("- deadline: '2026-11-01 23:59:59'")
            .renames(
                in: try catalog(
                    """
                    - deadline: '2026-11-08 23:59:59'
                      comment: Summer
                    - deadline: '2027-03-01 23:59:59'
                      comment: Winter
                    """))
        #expect(renames.isEmpty)
    }

    @Test func aRoundGoneWhileAnotherTakesItsIDLeavesNothingBehind() throws {
        let before = try catalog(
            """
            - deadline: '2026-09-01 23:59:59'
            - deadline: '2026-12-01 23:59:59'
            """)
        let after = try catalog("- deadline: '2026-12-01 23:59:59'")
        let following = Following(targetedEditions: [Following.Edition(series: "SC/dfrws", year: 2027)])
        var paper = Paper(title: "P", target: target, stage: .writing)
        paper.doneDeadlines = ["dfrws27|paper|#1"]
        var data = UserData(
            papers: [paper],
            lastSeen: ChangeDetector.detect(items: before.items(following: following), lastSeen: [:]).lastSeen)
        data.follow(before.renames(in: after), in: after)
        // The first round is gone, and its tick and the date seen for it with it.
        #expect(data.papers[0].doneDeadlines.isEmpty)
        #expect(data.lastSeen == ["dfrws27|paper|#1": "2026-12-01 23:59:59"])
        let changes = ChangeDetector.detect(items: after.items(following: following), lastSeen: data.lastSeen).changes
        #expect(changes.isEmpty)
    }

    @Test func roundsMergedIntoOneLeaveTheRestUnannounced() throws {
        // An abstract round and a paper round become one round with both.
        let before = try catalog(
            """
            - abstract_deadline: '2026-11-10 23:59:59'
              comment: Abstract
            - deadline: '2026-11-17 23:59:59'
              comment: Paper
            """)
        let after = try catalog(
            """
            - abstract_deadline: '2026-11-10 23:59:59'
              deadline: '2026-11-17 23:59:59'
            """)
        let renames = before.renames(in: after)
        #expect(renames.round("Paper", ofEdition: "dfrws27") == "#1")
        #expect(renames.round("Abstract", ofEdition: "dfrws27") == nil)
        let following = Following(targetedEditions: [Following.Edition(series: "SC/dfrws", year: 2027)])
        var data = UserData(
            lastSeen: ChangeDetector.detect(items: before.items(following: following), lastSeen: [:]).lastSeen)
        data.follow(renames, in: after)
        #expect(
            ChangeDetector.detect(items: after.items(following: following), lastSeen: data.lastSeen).changes.isEmpty)
    }

    @Test func aConferenceMovedToAnotherKeyKeepsItsStarsAndPapers() throws {
        let timeline = "- deadline: '2026-12-01 23:59:59'"
        let before = try catalog(timeline)
        let after = try catalog(timeline, key: "CG/dfrws")
        let renames = before.renames(in: after)
        #expect(renames.series("SC/dfrws") == "CG/dfrws" && renames.series("AI/cvpr") == "AI/cvpr")
        var round = target
        round.round = "#1"
        var data = UserData(
            favoriteSeries: ["SC/dfrws", "AI/cvpr"], papers: [Paper(title: "P", target: round)],
            settings: AppSettings(menuBarSubject: .series("SC/dfrws")))
        data.follow(renames, in: after)
        #expect(data.favoriteSeries == ["CG/dfrws", "AI/cvpr"])
        #expect(data.papers[0].target == Paper.Target(series: "CG/dfrws", year: 2027, round: "#1"))
        #expect(data.settings.menuBarSubject == .series("CG/dfrws"))
        #expect(PaperDeadlines.resolve(data.papers[0], catalog: after, now: referenceNow).main?.date != nil)
    }

    @Test func aChangeTheAlertCannotShowIsNotAnnounced() throws {
        let following = Following(targetedEditions: [Following.Edition(series: "SC/dfrws", year: 2027)])
        let before = try catalog("- deadline: '2026-10-01 23:59:00'")
        let seen = ChangeDetector.detect(items: before.items(following: following), lastSeen: [:]).lastSeen
        let after = try catalog("- deadline: '2026-10-01 23:59:59'")
        let result = ChangeDetector.detect(items: after.items(following: following), lastSeen: seen)
        #expect(result.changes.isEmpty && result.lastSeen["dfrws27|paper|#1"] == "2026-10-01 23:59:59")
        // A pass that announces nothing leaves a change for the next one that does.
        let moved = try catalog("- deadline: '2026-10-08 23:59:59'")
        let kept = ChangeDetector.record(items: moved.items(following: following), lastSeen: seen)
        #expect(kept == seen)
        #expect(ChangeDetector.detect(items: moved.items(following: following), lastSeen: kept).changes.count == 1)
    }
}
