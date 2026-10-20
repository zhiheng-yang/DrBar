import Foundation
import Testing

@testable import DrBarKit

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func temporaryFiles() throws -> AppFiles {
    let directory = FileManager.default.temporaryDirectory.appending(path: "drbar-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return AppFiles(directory: directory)
}

/// Every released `user.json` must keep decoding. Add a fixture for each release.
@Suite struct UserDataCompatibilityTests {
    @Test func decodesTheFirstRelease() throws {
        let (data, issues) = try UserDataStore.decode(fixture("user-v0.1.0"))
        #expect(issues.isEmpty)
        #expect(data.favoriteSeries == ["AI/cvpr", "DB/sigmod"] && data.papersPosition == 1)
        #expect(data.papers.map(\.title) == ["Efficient Video Diffusion", "Doctoral Fellowship"])
        let paper = data.papers[0]
        #expect(paper.target == Paper.Target(series: "AI/cvpr", year: 2027, round: "#1"))
        #expect(paper.stage == .writing && paper.doneDeadlines == ["cvpr27|abstract|#1"])
        #expect(paper.blocks.map(\.kind) == [.experiments, .writing, .custom, .buffer])
        let jane = data.mail.groups[0].people[0].id
        #expect(paper.blocks[2].customName == "Figures" && paper.blocks[1].people == [jane])
        #expect(paper.milestones.map(\.isDone) == [false, true] && paper.todos.map(\.isDone) == [true, false])
        #expect(paper.deadlines.first?.timeZone == "UTC-12" && paper.deadlines.first?.note == "Code and videos")
        let thread = try #require(paper.threads.first)
        #expect(thread.messageID == "0A1B2C3D-0001@example.org" && thread.includesOtherWork)
        #expect(paper.visibleTo == [jane] && paper.trackHeight == 26)
        let item = data.papers[1]
        #expect(item.groupID == data.groups[0].id && item.mainDeadline == item.deadlines.first?.id)
        #expect(data.groups.map(\.shownSymbol) == ["briefcase", "magnifyingglass"])
        #expect(data.archive.first?.stage == .decided && data.archive.first?.archivedAt != nil)
        #expect(data.recentlyDeleted.first?.group?.name == "Reviews" && data.recentlyDeleted.first?.index == 2)
        #expect(data.deletedParts.count == 4)
        #expect(data.mail.groups.map(\.kind) == [.supervisors, .collaborators, .other])
        #expect(data.mail.groups[1].language == .chinese && data.mail.senderAddress == "alex@example.edu")
        #expect(data.settings.menuBarSubject == .paper(paper.id) && data.settings.axisRange == .sixMonths)
        #expect(data.settings.rowSize == .small && data.settings.reminderDays == [14, 3])
        #expect(!data.settings.blockReminders && data.settings.notificationsEnabled)
        #expect(data.lastSeen["cvpr27|paper|#1"] == "2026-11-16 23:59:59")
    }

    /// What the builds before the first release wrote, with the deadlines they kept in a list of
    /// their own and the range in months.
    @Test func decodesTheBuildsBeforeTheFirstRelease() throws {
        let (data, issues) = try UserDataStore.decode(fixture("user-preview"))
        #expect(issues.isEmpty)
        #expect(data.favoriteSeries == ["AI/cvpr", "AI/iclr"])
        #expect(data.papers.count == 3)
        let paper = data.papers[0]
        #expect(paper.title == "Efficient Video Diffusion")
        #expect(paper.target == Paper.Target(series: "AI/cvpr", year: 2027))
        #expect(paper.deadlines.isEmpty && paper.doneDeadlines.isEmpty && paper.mainDeadline == nil)
        #expect(paper.stage == .writing)
        #expect(paper.blocks.map(\.kind) == [.experiments, .custom])
        #expect(paper.blocks[1].customName == "Figures")
        #expect(paper.blocks[0].start == Day(year: 2026, month: 10, day: 12))
        #expect(paper.milestones.map(\.title) == ["Draft to supervisor"])
        #expect(paper.milestones.first?.day == Day(year: 2026, month: 10, day: 30))
        #expect(paper.trackHeight == 28)
        #expect(data.papers[1].milestones.isEmpty)
        #expect(data.papers[1].trackHeight == nil)
        let supervisors = try #require(data.mail.groups.first)
        #expect(supervisors.kind == .supervisors)
        #expect(paper.blocks[0].people == supervisors.people.map(\.id))
        #expect(paper.blocks[1].people.isEmpty)
        #expect(paper.thread(for: supervisors.id)?.messageID == "0A1B2C3D-0001@example.org")
        // Everything stays the user's own, and no update told of other work.
        #expect(data.papers.allSatisfy { $0.visibleTo.isEmpty })
        #expect(paper.thread(for: supervisors.id)?.includesOtherWork == false)
        #expect(paper.todos.map(\.title) == ["Rerun the baselines", "Add ablation table 3"])
        #expect(data.papers[1].todos.isEmpty)
        // The deadline of its own it aimed at moved into it, as the one it aims at.
        let workshop = UUID(uuidString: "8C1E3D5A-6F0B-4C47-9C9E-3A1F2B7D4E60")!
        #expect(data.papers[1].target == nil && data.papers[1].mainDeadline == workshop)
        #expect(data.papers[1].deadlines.map(\.id) == [workshop])
        #expect(data.papers[1].deadlines.first?.timeZone == "AoE" && data.papers[1].deadlines.first?.isDone == false)
        #expect(data.groups.map(\.name) == ["Applications"])
        #expect(data.items(in: nil).map(\.title) == ["Efficient Video Diffusion", "RL Benchmark"])
        let application = try #require(data.items(in: data.groups[0].id).first)
        #expect(application.title == "Doctoral Fellowship" && !application.isPaper)
        #expect(application.blocks.map(\.kind) == [.writing])
        #expect(application.deadlines.count == 1 && application.mainDeadline == application.deadlines.first?.id)
        #expect(data.listedDeadlines.isEmpty)
        #expect(data.settings.rowSize == .large)
        #expect(data.settings.categories == ["AI", "CG"])
        #expect(data.settings.notificationsEnabled)
        #expect(supervisors.recipients.map(\.address) == ["supervisor@example.org"])
        #expect(data.mail.groups[1].recipients.map(\.name) == ["Li", "Sam"])
        #expect(data.mail.groups[1].language == .chinese)
        #expect(data.mail.signature == "Ada")
        #expect(data.lastSeen["cvpr27|paper|#1"] == "2026-11-16 23:59:59")
    }

    @Test func everyFieldSurvivesARoundTrip() throws {
        var data = try UserDataStore.decode(fixture("user-preview")).data
        data.settings = AppSettings(
            categories: ["DB"], ccfRanks: ["C"], notificationsEnabled: true, reminderDays: [14],
            blockReminders: false, dateChangeAlerts: false, menuBarStyle: .days, menuBarSubject: .series("AI/cvpr"),
            axisRange: .week, axisLabels: .both, rowSize: .small, appearance: .dark)
        data.mail.groups.append(
            RecipientGroup(
                kind: .other, name: "Reading group", people: [Person(name: "N", email: "n@example.org")],
                language: .chinese, hidesBufferBlocks: false))
        data.mail.senderAddress = "me@example.org"
        data.papers[0].blocks[1].people = [data.mail.groups[0].people[0].id]
        data.papers[0].trackHeight = 27
        data.papers[0].milestones = [
            Milestone(title: "Internal deadline", day: Day(year: 2026, month: 11, day: 1)),
            Milestone(title: "Draft to Jane", day: Day(year: 2026, month: 10, day: 20), isDone: true),
        ]
        data.papers[1].keep(
            MailThread(
                groupID: data.mail.groups[2].id, subject: "Progress",
                startedAt: Date(timeIntervalSince1970: 1_790_000_000), includesOtherWork: true))
        data.papers[1].visibleTo = [data.mail.groups[0].people[0].id]
        data.papers[0].target = Paper.Target(series: "DB/sigmod", year: 2027, round: "round 4")
        data.papers[0].doneDeadlines = ["sigmod27|abstract|round 4"]
        data.papers[0].deadlines = [
            CustomDeadline(title: "Camera-ready", date: Date(timeIntervalSince1970: 1_810_000_000), isDone: true)
        ]
        let own = CustomDeadline(title: "TACL", date: Date(timeIntervalSince1970: 1_800_000_000))
        data.papers[1].deadlines.append(own)
        data.papers[1].mainDeadline = own.id
        data.groups.append(ItemGroup(name: "Reviews"))
        data.papersPosition = 1
        data.delete(
            [data.papers[0].blocks[0].id, data.papers[0].milestones[0].id, own.id],
            now: Date(timeIntervalSince1970: 1_795_000_000))
        let again = try UserDataStore.decode(UserDataStore.encode(data))
        #expect(again.issues.isEmpty)
        #expect(again.data == data)
    }

    @Test func theAxisShowsDatesDaysOrBoth() {
        #expect(AppSettings.AxisLabels.showing(dates: true, days: true) == .both)
        #expect(AppSettings.AxisLabels.showing(dates: false, days: true) == .days)
        #expect(AppSettings.AxisLabels.showing(dates: true, days: false) == .dates)
        #expect(AppSettings.AxisLabels.both.showsDates && AppSettings.AxisLabels.both.showsDays)
        #expect(!AppSettings.AxisLabels.days.showsDates && !AppSettings.AxisLabels.dates.showsDays)
    }

    @Test func peopleLeaveWhatTheyCouldSeeWithTheirGroup() throws {
        var data = try UserDataStore.decode(fixture("user-preview")).data
        let supervisor = data.mail.groups[0].people[0].id
        let li = data.mail.groups[1].people[0].id
        data.papers[0].visibleTo = [li, supervisor]
        data.archive = [Paper(title: "Archived", visibleTo: [li])]
        data.recentlyDeleted = [DeletedPaper(paper: Paper(title: "Deleted", visibleTo: [li]), deletedAt: Date())]
        data.removeRecipientGroup(data.mail.groups[1].id)
        #expect(data.papers[0].visibleTo == [supervisor])
        #expect(data.archive[0].visibleTo.isEmpty && data.recentlyDeleted[0].paper.visibleTo.isEmpty)
    }

    @Test func deadlinesOfTheOldListBecomeSomeonesOwn() throws {
        let workshop = CustomDeadline(title: "Workshop", date: Date(timeIntervalSince1970: 1_800_000_000))
        let fellowship = CustomDeadline(title: "Fellowship", date: Date(timeIntervalSince1970: 1_801_000_000))
        var data = UserData(
            papers: [
                Paper(title: "Paper", mainDeadline: workshop.id), Paper(title: "Again", mainDeadline: workshop.id),
            ],
            listedDeadlines: [workshop, fellowship])
        data.settings.menuBarSubject = .customDeadline(fellowship.id)
        let changed = data.moveListedDeadlines(intoGroupNamed: "Deadlines")
        #expect(changed && data.listedDeadlines.isEmpty)
        // The papers that aimed at one get it, each its own copy; the other goes to an item of a new
        // group.
        #expect(data.papers[0].deadlines.map(\.id) == [workshop.id] && data.papers[0].deadlines[0].title == "Workshop")
        #expect(data.papers[1].deadlines.count == 1 && data.papers[1].mainDeadline == data.papers[1].deadlines[0].id)
        #expect(data.papers[1].deadlines[0].id != workshop.id)
        #expect(data.groups.map(\.name) == ["Deadlines"])
        let item = try #require(data.items(in: data.groups[0].id).first)
        #expect(item.title == "Fellowship" && item.mainDeadline == fellowship.id)
        #expect(item.deadlines.map(\.id) == [fellowship.id] && item.deadlines[0].title.isEmpty)
        #expect(data.settings.menuBarSubject == .paper(item.id))
        let moved = data
        let changedAgain = data.moveListedDeadlines(intoGroupNamed: "Deadlines")
        #expect(!changedAgain && data == moved)
        var current = try UserDataStore.decode(fixture("user-preview")).data
        let changesCurrent = current.moveListedDeadlines(intoGroupNamed: "Deadlines")
        #expect(!changesCurrent)
    }

    @Test func deadlinesKeptBesideTheirPapersMoveIntoThem() throws {
        let paper = UUID()
        let deleted = UUID()
        let json = """
            {"papers": [{"id": "\(paper)", "title": "P", "target": {"custom": {"id": "8C1E3D5A-6F0B-4C47-9C9E-3A1F2B7D4E60"}}}],
             "customDeadlines": [
               {"id": "8C1E3D5A-6F0B-4C47-9C9E-3A1F2B7D4E60", "title": "Workshop", "date": "2026-11-17T11:59:00Z", "paperID": "\(paper)"},
               {"id": "9C1E3D5A-6F0B-4C47-9C9E-3A1F2B7D4E60", "title": "Gone", "date": "2026-11-17T11:59:00Z", "paperID": "\(deleted)"}],
             "recentlyDeleted": [{"paper": {"id": "\(deleted)", "title": "D"}, "deletedAt": "2026-10-01T00:00:00Z",
               "deadlines": [{"id": "AC1E3D5A-6F0B-4C47-9C9E-3A1F2B7D4E60", "title": "Kept", "date": "2026-11-17T11:59:00Z"}]}]}
            """
        let (data, issues) = try UserDataStore.decode(Data(json.utf8))
        #expect(issues.isEmpty)
        #expect(data.papers[0].deadlines.map(\.title) == ["Workshop"] && data.papers[0].target == nil)
        #expect(data.papers[0].mainDeadline == data.papers[0].deadlines.first?.id)
        #expect(data.recentlyDeleted[0].paper.deadlines.map(\.title).sorted() == ["Gone", "Kept"])
        #expect(data.listedDeadlines.isEmpty)
        let saved = try UserDataStore.encode(data)
        #expect(!String(decoding: saved, as: UTF8.self).contains("customDeadlines"))
    }

    @Test func everyPaperThatAimedAtADeadlineGetsItsOwn() throws {
        let owner = UUID()
        let workshop = UUID()
        let lost = UUID()
        let json = """
            {"papers": [{"id": "\(owner)", "title": "P", "target": {"custom": {"id": "\(workshop)"}}},
                        {"id": "\(UUID())", "title": "Q", "target": {"custom": {"id": "\(lost)"}}}],
             "archive": [{"id": "\(UUID())", "title": "A", "target": {"custom": {"id": "\(workshop)"}}}],
             "customDeadlines": [
               {"id": "\(workshop)", "title": "Workshop", "date": "2026-11-17T11:59:00Z", "paperID": "\(owner)"},
               {"id": "\(lost)", "title": "Lost", "date": "2026-11-20T11:59:00Z", "paperID": "\(UUID())"}]}
            """
        var (data, issues) = try UserDataStore.decode(Data(json.utf8))
        #expect(issues.isEmpty)
        // An archived paper too gets a copy of the deadline that another paper kept.
        #expect(data.archive[0].deadlines.map(\.title) == ["Workshop"])
        #expect(data.archive[0].mainDeadline == data.archive[0].deadlines.first?.id)
        // One whose paper is gone waits in the list, then goes once to the paper that aimed at it.
        #expect(data.listedDeadlines.map(\.title) == ["Lost"] && data.papers[1].deadlines.isEmpty)
        data.moveListedDeadlines(intoGroupNamed: "Deadlines")
        #expect(data.papers[1].deadlines.map(\.title) == ["Lost"] && data.groups.isEmpty)
    }

    @Test func anArchivedPaperKeepsTheListedDeadlineItAimedAt() throws {
        let listed = UUID()
        let json = """
            {"archive": [{"id": "\(UUID())", "title": "A", "target": {"custom": {"id": "\(listed)"}}}],
             "customDeadlines": [{"id": "\(listed)", "title": "Workshop", "date": "2026-11-17T11:59:00Z"}]}
            """
        var data = try UserDataStore.decode(Data(json.utf8)).data
        data.moveListedDeadlines(intoGroupNamed: "Deadlines")
        #expect(data.archive[0].deadlines.map(\.title) == ["Workshop"] && data.archive[0].mainDeadline == listed)
        #expect(data.groups.isEmpty && data.papers.isEmpty)
    }

    @Test func itemsOfAGroupThatCouldNotBeReadJoinThePapers() throws {
        let group = UUID()
        let json = """
            {"groups": [{"id": "not an id", "name": "Applications"}],
             "papers": [{"title": "Fellowship", "groupID": "\(group)"}],
             "archive": [{"title": "Grant", "groupID": "\(group)"}]}
            """
        let (data, issues) = try UserDataStore.decode(Data(json.utf8))
        #expect(data.groups.map(\.name) == ["Applications"] && !issues.isEmpty)
        #expect(data.papers[0].groupID == nil && data.archive[0].groupID == nil)
        #expect(data.items(in: nil).map(\.title) == ["Fellowship"])
    }

    @Test func theRangeOfEarlierBuildsIsReadInMonths() throws {
        func range(_ settings: String) throws -> (AxisRange, Int) {
            let (data, issues) = try UserDataStore.decode(Data(#"{"settings": \#(settings)}"#.utf8))
            return (data.settings.axisRange, issues.count)
        }
        #expect(try range(#"{"axisMonths": 1}"#) == (.month, 0))
        #expect(try range(#"{"axisMonths": 6}"#) == (.sixMonths, 0))
        #expect(try range(#"{"axisMonths": 5}"#) == (.threeMonths, 0))
        #expect(try range(#"{"axisRange": "week", "axisMonths": 3}"#) == (.week, 0))
        #expect(try range(#"{"axisRange": "fortnight"}"#) == (.threeMonths, 1))
        let saved = String(
            decoding: try UserDataStore.encode(UserData(settings: AppSettings(axisRange: .week))), as: UTF8.self)
        #expect(saved.contains(#""axisRange" : "week""#) && !saved.contains("axisMonths"))
    }

    @Test func encodingIsStable() throws {
        let data = try UserDataStore.decode(fixture("user-preview")).data
        #expect(try UserDataStore.encode(data) == UserDataStore.encode(data))
    }

    @Test func theFirstBuildsSupervisorBecomesTheSupervisorsGroup() throws {
        let json = #"""
            {
              "papers": [{"title": "Paper", "supervisorThread": {"subject": "Progress", "startedAt": "2026-09-20T10:00:00Z"}}],
              "supervisor": {"name": "Dr. Example", "email": "supervisor@example.org", "signature": "Ada",
                             "language": "zh-Hans", "hidesBufferBlocks": false}
            }
            """#
        let (data, issues) = try UserDataStore.decode(Data(json.utf8))
        #expect(issues.isEmpty)
        let supervisors = try #require(data.mail.groups.first)
        #expect(supervisors.kind == .supervisors)
        #expect(supervisors.people.map(\.name) == ["Dr. Example"])
        #expect(supervisors.language == .chinese)
        #expect(!supervisors.hidesBufferBlocks)
        #expect(data.mail.groups.map(\.kind) == [.supervisors, .collaborators])
        #expect(data.mail.signature == "Ada")
        #expect(data.papers[0].threads.map(\.groupID) == [supervisors.id])
        #expect(!String(decoding: try UserDataStore.encode(data), as: UTF8.self).contains("supervisorThread"))
    }

    @Test func removingAGroupForgetsItsThreadsWhereverTheWorkIs() throws {
        var data = try UserDataStore.decode(fixture("user-preview")).data
        let supervisors = data.mail.groups[0].id
        let thread = try #require(data.papers[0].thread(for: supervisors))
        #expect(UserData(archive: [Paper(title: "Archived", threads: [thread])]).hasThreads(with: supervisors))
        data.archive = [Paper(title: "Archived", threads: [thread])]
        data.recentlyDeleted = [DeletedPaper(paper: Paper(title: "Deleted", threads: [thread]), deletedAt: Date())]
        data.removeRecipientGroup(supervisors)
        #expect(data.mail.groups.map(\.kind) == [.collaborators])
        #expect(data.papers[0].threads.isEmpty && !data.hasThreads(with: supervisors))
    }

    @Test func blankRowsAreDroppedAndOnlyAddressesAreRecipients() {
        var mail = MailSettings()
        mail.groups[0].people = [
            Person(name: "Jane", email: " jane@example.org "), Person(name: " ", email: ""),
            Person(name: "No address", email: ""), Person(email: "not an address"), Person(email: "a@b@c"),
        ]
        #expect(mail.groups[0].recipients.map(\.address) == ["jane@example.org"])
        mail.removeBlankPeople()
        #expect(mail.groups[0].people.count == 4)
    }

    @Test func monograms() {
        #expect(Person(name: "Prof. Jane Doe").initials == "JD")
        #expect(Person(name: "mia chen").initials == "MC")
        #expect(Person(name: "Mia").initials == "M")
        #expect(Person(name: "李明").initials == "李")
        #expect(Person(name: "欧阳娜娜").initials == "欧")
        #expect(Person(email: "sam@example.org").initials == "S")
        #expect(Person().initials.isEmpty)
    }

    @Test func peopleLeaveTheBlocksWithTheirGroup() throws {
        var data = try UserDataStore.decode(fixture("user-preview")).data
        let li = data.mail.groups[1].people[0].id
        let supervisor = data.mail.groups[0].people[0].id
        data.papers[0].blocks[0].people = [supervisor, li]
        #expect(data.people[li]?.name == "Li")
        data.removeRecipientGroup(data.mail.groups[1].id)
        #expect(data.papers[0].blocks[0].people == [supervisor])
        #expect(data.papers[0].blocks[0].nextRound().people == [supervisor])
    }

    @Test func missingFieldsGetDefaults() throws {
        let (data, issues) = try UserDataStore.decode(Data("{}".utf8))
        #expect(issues.isEmpty)
        #expect(data == UserData())
        let (paper, paperIssues) = try UserDataStore.decode(Data(#"{"papers":[{"title":"Only a title"}]}"#.utf8))
        #expect(paperIssues.isEmpty)
        #expect(paper.papers.first?.stage == .idea)
        #expect(paper.papers.first?.blocks.isEmpty == true)
    }

    @Test func badEntriesAreSkippedAndReported() throws {
        let json = #"""
            {
              "favoriteSeries": "AI/cvpr",
              "papers": [
                {"title": "Good", "blocks": [
                  {"kind": "writing", "start": "2026-10-01", "end": "2026-10-05"},
                  {"kind": "writing", "start": "yesterday", "end": "2026-10-05"},
                  {"kind": "poster", "start": "2026-10-06", "end": "2026-10-07"}
                ]},
                42
              ],
              "settings": {"axisMonths": 5, "menuBarStyle": "neon"}
            }
            """#
        let (data, issues) = try UserDataStore.decode(Data(json.utf8))
        #expect(data.papers.map(\.title) == ["Good"])
        // A block kind from a newer version becomes a custom block that keeps its name.
        #expect(data.papers[0].blocks.map(\.kind) == [.writing, .custom])
        #expect(data.papers[0].blocks[1].customName == "poster")
        #expect(data.settings.axisRange == .threeMonths)
        #expect(data.settings.menuBarStyle == .bar)
        #expect(data.favoriteSeries.isEmpty)
        #expect(issues.count == 4)  // favoriteSeries, one block, one paper, menuBarStyle
    }

    @Test func whatAFileHoldsTwiceIsReadOnce() throws {
        let block = TimeBlock(
            kind: .writing, start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 9))
        let paper = Paper(title: "P", blocks: [block, block])
        let repeats = UserData(papers: [paper, paper], archive: [paper])
        let (read, issues) = try UserDataStore.decode(UserDataStore.encode(repeats))
        #expect(read.papers.map(\.id) == [paper.id] && read.papers[0].blocks.map(\.id) == [block.id])
        #expect(read.archive.isEmpty && issues.isEmpty)
        // Something else with an id already taken is left out too, and said.
        var review = block
        review.kind = .review
        var twin = paper
        twin.title = "Twin"
        twin.blocks = [block, review]
        let mixed = try UserDataStore.decode(UserDataStore.encode(UserData(papers: [paper, twin])))
        #expect(mixed.data.papers.map(\.title) == ["P"] && mixed.issues.count == 2)
    }
}

@Suite struct UserDataStoreTests {
    @Test func firstLaunchStartsEmpty() throws {
        var store = UserDataStore(files: try temporaryFiles())
        let (data, outcome) = store.load()
        #expect(data == UserData())
        #expect(outcome == .fresh)
    }

    @Test func savingKeepsABackupOfThePreviousFile() throws {
        let files = try temporaryFiles()
        var store = UserDataStore(files: files)
        try store.save(UserData(favoriteSeries: ["AI/a"]))
        try store.save(UserData(favoriteSeries: ["AI/b"]))
        #expect(try UserDataStore.decode(Data(contentsOf: files.userDataBackup)).data.favoriteSeries == ["AI/a"])
        let (data, outcome) = store.load()
        #expect(data.favoriteSeries == ["AI/b"])
        #expect(outcome == .loaded)
    }

    @Test func unreadableFileFallsBackToTheBackupAndIsKept() throws {
        let files = try temporaryFiles()
        var store = UserDataStore(files: files)
        try store.save(UserData(favoriteSeries: ["AI/a"]))
        try store.save(UserData(favoriteSeries: ["AI/b"]))
        try Data("{ not json".utf8).write(to: files.userData)

        let (data, outcome) = store.load()
        #expect(data.favoriteSeries == ["AI/a"])
        guard case let .restoredFromBackup(copy?, isPartial: false) = outcome else {
            Issue.record("Expected a restore, got \(outcome)")
            return
        }
        #expect(try String(contentsOf: copy, encoding: .utf8) == "{ not json")
        // The restored data replaced the broken file, and the good backup is still there.
        #expect(try UserDataStore.decode(Data(contentsOf: files.userData)).data.favoriteSeries == ["AI/a"])
        #expect(try UserDataStore.decode(Data(contentsOf: files.userDataBackup)).data.favoriteSeries == ["AI/a"])
    }

    @Test func aBackupReadInPartIsCopiedBeforeItIsReplaced() throws {
        let files = try temporaryFiles()
        let backup = #"{"papers":[{"title":"Kept"}, 7]}"#
        try Data(backup.utf8).write(to: files.userDataBackup)
        try Data("{ not json".utf8).write(to: files.userData)
        var store = UserDataStore(files: files)
        let (data, outcome) = store.load()
        #expect(data.papers.map(\.title) == ["Kept"])
        guard case .restoredFromBackup(_, isPartial: true) = outcome else {
            Issue.record("Expected a partial restore, got \(outcome)")
            return
        }
        // Saving twice replaces the backup; what it held is still in a copy.
        try store.save(data)
        try store.save(data)
        #expect(try copies(in: files).contains(backup))
    }

    @Test func aMissingFileWithAnUnreadableBackupIsSaid() throws {
        let files = try temporaryFiles()
        try Data("{ not json".utf8).write(to: files.userDataBackup)
        var store = UserDataStore(files: files)
        let (data, outcome) = store.load()
        #expect(data == UserData())
        guard case let .unreadable(copy?) = outcome else {
            Issue.record("Expected an unreadable backup, got \(outcome)")
            return
        }
        #expect(try String(contentsOf: copy, encoding: .utf8) == "{ not json")
        try store.save(data)
        try store.save(data)
        #expect(try copies(in: files).contains("{ not json"))
    }

    @Test func aFileThatCannotBeReadNeverBecomesTheBackup() throws {
        let files = try temporaryFiles()
        var store = UserDataStore(files: files)
        try store.save(UserData(favoriteSeries: ["AI/a"]))
        try store.save(UserData(favoriteSeries: ["AI/b"]))
        try Data("{ not json".utf8).write(to: files.userData)
        try store.save(UserData(favoriteSeries: ["AI/c"]))
        #expect(try UserDataStore.decode(Data(contentsOf: files.userDataBackup)).data.favoriteSeries == ["AI/a"])
        #expect(try UserDataStore.decode(Data(contentsOf: files.userData)).data.favoriteSeries == ["AI/c"])
        #expect(try copies(in: files) == ["{ not json"])
    }

    @Test func aPartlyReadableFileIsSetAsideAndRewrittenAtOnce() throws {
        let files = try temporaryFiles()
        var store = UserDataStore(files: files)
        try store.save(UserData(favoriteSeries: ["AI/a"]))
        try store.save(UserData(favoriteSeries: ["AI/b"]))
        let partly = #"{"favoriteSeries":["AI/c"],"papers":[{"title":"Kept"}, 7]}"#
        try Data(partly.utf8).write(to: files.userData)
        let (data, _) = store.load()
        let written = try UserDataStore.decode(Data(contentsOf: files.userData))
        #expect(written.issues.isEmpty && written.data.papers.map(\.id) == data.papers.map(\.id))
        try store.save(data)
        // Only the file written in its place became the backup; it is in the copy as it was.
        let backup = try UserDataStore.decode(Data(contentsOf: files.userDataBackup)).data
        #expect(backup.favoriteSeries == ["AI/c"] && backup.papers.map(\.title) == ["Kept"])
        #expect(try copies(in: files) == [partly])
        // Nothing is copied again at the next launch.
        #expect(store.load().1 == .loaded)
    }

    @Test func aFileThatCannotBeCopiedIsMovedAsideBeforeItIsWrittenOver() throws {
        let files = try temporaryFiles()
        let original = try UserDataStore.encode(UserData(favoriteSeries: ["AI/a"]))
        try original.write(to: files.userData)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: files.userData.path)
        var store = UserDataStore(files: files)
        let (data, outcome) = store.load()
        #expect(data == UserData())
        guard case let .unreadable(kept?) = outcome else {
            Issue.record("Expected the file to be set aside, got \(outcome)")
            return
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: kept.path)
        #expect(try Data(contentsOf: kept) == original)
        #expect(try UserDataStore.decode(Data(contentsOf: files.userData)).data == UserData())
    }

    @Test func aFileThatCannotBeWrittenLeavesTheBackupAlone() throws {
        let files = try temporaryFiles()
        var store = UserDataStore(files: files)
        try store.save(UserData(favoriteSeries: ["AI/a"]))
        try store.save(UserData(favoriteSeries: ["AI/b"]))
        try Data("{ not json".utf8).write(to: files.userData)
        // Locked, as in the Finder: it can be neither replaced nor restored.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: files.userData.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: files.userData.path)
            try? FileManager.default.removeItem(at: files.directory)
        }
        #expect(store.load().0.favoriteSeries == ["AI/a"])
        #expect(throws: (any Error).self) { try store.save(UserData(favoriteSeries: ["AI/c"])) }
        #expect(store.load(now: Date().addingTimeInterval(3600)).0.favoriteSeries == ["AI/a"])
        // It is copied once, however often it is read, and the copy is not locked.
        let names = try FileManager.default.contentsOfDirectory(atPath: files.directory.path)
        let copies = names.filter { $0.contains(".unreadable-") }
        #expect(copies.count == 1)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: files.directory.appending(path: copies[0]).path)
        #expect(attributes[.immutable] as? Bool == false)
    }

    @Test func aLockedFileLeavesAnUnlockedBackup() throws {
        let files = try temporaryFiles()
        var store = UserDataStore(files: files)
        try store.save(UserData(favoriteSeries: ["AI/a"]))
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: files.userData.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: files.userData.path)
            try? FileManager.default.removeItem(at: files.directory)
        }
        #expect(throws: (any Error).self) { try store.save(UserData(favoriteSeries: ["AI/b"])) }
        // Unlocked again, it saves as before.
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: files.userData.path)
        try store.save(UserData(favoriteSeries: ["AI/c"]))
        #expect(try UserDataStore.decode(Data(contentsOf: files.userData)).data.favoriteSeries == ["AI/c"])
    }

    /// The copies of unreadable files kept in the data folder, as text.
    func copies(in files: AppFiles) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: files.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".unreadable-") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
    }

    @Test func partlyReadableFileIsCopiedBeforeAnythingIsLost() throws {
        let files = try temporaryFiles()
        try Data(#"{"papers":[{"title":"Kept"}, 7]}"#.utf8).write(to: files.userData)
        var store = UserDataStore(files: files)
        let (data, outcome) = store.load()
        #expect(data.papers.map(\.title) == ["Kept"])
        guard case let .repaired(copy?) = outcome else {
            Issue.record("Expected a repair with a copy, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func importTakesOnlyDrBarData() throws {
        let exported = try UserDataStore.encode(UserData(favoriteSeries: ["AI/a"]))
        #expect(try UserDataStore.decodeExported(exported).data.favoriteSeries == ["AI/a"])
        #expect(throws: (any Error).self) { try UserDataStore.decodeExported(Data(#"{"name":"other"}"#.utf8)) }
        #expect(throws: (any Error).self) { try UserDataStore.decodeExported(Data("[]".utf8)) }
    }

    @Test func jsonFileRoundTrips() throws {
        let directory = try temporaryFiles().directory
        let deadlines = [CustomDeadline(title: "Workshop", date: Date(timeIntervalSince1970: 1_800_000_000))]
        try JSONFile.write(deadlines, to: directory.appending(path: "deadlines.json"))
        #expect(JSONFile.read([CustomDeadline].self, from: directory.appending(path: "deadlines.json")) == deadlines)
        #expect(JSONFile.read([CustomDeadline].self, from: directory.appending(path: "missing.json")) == nil)
    }
}

@Suite struct LibraryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let group = ItemGroup(name: "Applications")
    var data: UserData {
        let first = Paper(title: "First", createdAt: now)
        let second = Paper(title: "Second", createdAt: now)
        let own = CustomDeadline(title: "", date: now.addingTimeInterval(86_400 * 20))
        let item = Paper(title: "Fellowship", deadlines: [own], mainDeadline: own.id, groupID: group.id, createdAt: now)
        return UserData(papers: [first, second, item], groups: [group])
    }

    @Test func deletedWorkComesBackWhereItWas() throws {
        var data = data
        let first = data.papers[0].id
        let item = data.papers[2].id
        data.delete([first, item], now: now)
        #expect(data.papers.map(\.title) == ["Second"])
        #expect(data.recentlyDeleted.map(\.paper.title) == ["First", "Fellowship"])
        #expect(data.recentlyDeleted[1].paper.deadlines.count == 1)
        data.recover([item, first])
        #expect(data.papers.map(\.title) == ["First", "Second", "Fellowship"])
        #expect(data.papers[2].deadlines.count == 1 && data.recentlyDeleted.isEmpty)
    }

    @Test func aDeletedGroupComesBackWithItsItems() throws {
        var data = data
        let item = data.papers[2].id
        let reviews = ItemGroup(name: "Reviews")
        data.insertGroup(reviews, at: 0)
        #expect(data.groupOrder == [reviews.id, nil, group.id])
        #expect(data.deleteGroup(reviews.id, now: now).isEmpty)
        data.insertGroup(reviews, at: 0)
        #expect(data.deleteGroup(group.id, now: now) == [item])
        #expect(data.groups == [reviews] && data.recentlyDeleted.first?.groupPosition == 2)
        data.recover([item])
        #expect(data.groupOrder == [reviews.id, nil, group.id])
        #expect(data.items(in: group.id).map(\.title) == ["Fellowship"])
        // Without its group, an item comes back among the papers.
        data.groups.removeAll()
        data.delete([item], now: now)
        data.recover([item])
        #expect(data.items(in: nil).map(\.title).contains("Fellowship"))
    }

    @Test func recentlyDeletedKeepsThirtyDays() {
        var data = data
        data.delete([data.papers[0].id], now: now)
        let entry = data.recentlyDeleted[0]
        #expect(entry.daysLeft(now: now) == 30)
        #expect(entry.daysLeft(now: now.addingTimeInterval(86_400 * 29.5)) == 1)
        let early = data.purgeRecentlyDeleted(now: now.addingTimeInterval(86_400 * 29))
        let due = data.purgeRecentlyDeleted(now: now.addingTimeInterval(86_400 * 30))
        #expect(!early && due)
        #expect(data.recentlyDeleted.isEmpty)
        data.delete([data.papers[0].id], now: now)
        data.deleteForever([data.recentlyDeleted[0].id])
        #expect(data.recentlyDeleted.isEmpty && data.papers.count == 1)
    }

    @Test func deletedPartsComeBackWhereTheyWere() throws {
        let blocks = (0..<3).map {
            TimeBlock(kind: .writing, start: Day(now).adding($0 * 10), end: Day(now).adding($0 * 10 + 5))
        }
        let milestone = Milestone(title: "Draft", day: Day(now).adding(4))
        let todos = [TodoItem(title: "Seeds"), TodoItem(title: "Table")]
        var data = data
        data.papers[0].blocks = blocks
        data.papers[0].milestones = [milestone]
        data.papers[0].todos = todos
        let own = data.papers[2].deadlines[0]
        let deleted = data.delete([blocks[1].id, milestone.id, own.id, todos[0].id], now: now)
        #expect(deleted.count == 4)
        #expect(data.papers[0].blocks.map(\.id) == [blocks[0].id, blocks[2].id])
        #expect(data.papers[0].milestones.isEmpty && data.papers[0].todos.map(\.title) == ["Table"])
        #expect(data.papers[2].deadlines.isEmpty && data.papers[2].mainDeadline == nil)
        #expect(data.deletedParts.map(\.index) == [1, 0, 0, 0] && data.recentlyDeleted.isEmpty)
        #expect(data.deletedParts.allSatisfy { $0.daysLeft(now: now) == 30 })
        let again = try UserDataStore.decode(UserDataStore.encode(data))
        #expect(again.issues.isEmpty && again.data == data)
        let recovered = data.recover(data.deletedParts.map(\.id))
        #expect(Set(recovered.ids) == Set(deleted))
        #expect(data.papers[0].blocks == blocks && data.papers[0].milestones == [milestone])
        #expect(data.papers[0].todos == todos && data.deletedParts.isEmpty)
        #expect(data.papers[2].deadlines == [own] && data.papers[2].mainDeadline == own.id)
    }

    @Test func aPartBringsBackItsPaperOrGoesWithIt() {
        var data = data
        let block = TimeBlock(kind: .writing, start: Day(now), end: Day(now).adding(9))
        data.papers[1].blocks = [block]
        let paper = data.papers[1].id
        data.delete([block.id], now: now)
        data.delete([paper], now: now.addingTimeInterval(60))
        #expect(data.deletedEntries.map(\.id) == [paper, block.id])
        // The paper comes back with the block, to be deleted again with it.
        let recovered = data.recover([block.id])
        #expect(recovered.ids == [block.id, paper])
        #expect(data.papers.map(\.title) == ["First", "Second", "Fellowship"])
        #expect(data.papers[1].blocks == [block] && !data.hasDeletedEntries)
        data.delete([block.id, paper], now: now)
        #expect(data.deletedParts.count == 1 && data.recentlyDeleted.count == 1)
        // Deleted for good, the paper takes what was deleted from it.
        data.deleteForever([paper])
        #expect(!data.hasDeletedEntries)
        data.delete([data.papers[0].id], now: now)
        let todo = TodoItem(title: "Seeds")
        data.papers[0].todos = [todo]
        data.delete([todo.id], now: now.addingTimeInterval(86_400 * 10))
        let purged = data.purgeRecentlyDeleted(now: now.addingTimeInterval(86_400 * 30))
        #expect(purged)
        #expect(data.deletedParts.map(\.id) == [todo.id] && data.recentlyDeleted.isEmpty)
    }

    @Test func whatCameBackGoesBackAsItWas() {
        var data = data
        let item = data.papers[2]
        let own = item.deadlines[0]
        // An item deleted with its group, then one of its deadlines deleted before.
        let later = CustomDeadline(title: "Interview", date: now.addingTimeInterval(86_400 * 40))
        data.addDeadline(later, to: item.id, now: now)
        data.delete([own.id], now: now)
        #expect(data.papers[2].mainDeadline == later.id)
        data.deleteGroup(group.id, now: now.addingTimeInterval(60))
        let before = data
        // Recovered: the group comes back, and the item aims at its first deadline again.
        let recovery = data.recover([own.id])
        #expect(recovery.ids == [own.id, item.id] && data.groups == [group])
        #expect(data.papers.last?.mainDeadline == own.id)
        data.papers[data.papers.count - 1].title = "Fellowship 2027"
        // Put back, everything is as it was in Recently Deleted, but for the new title.
        #expect(Set(data.putBack(recovery, now: now)) == [own.id, item.id])
        var expected = before
        expected.recentlyDeleted[0].paper.title = "Fellowship 2027"
        #expect(data == expected)
        #expect(data.recentlyDeleted[0].group == group && data.deletedParts[0].deletedAt == now)
    }

    @Test func aPartOfAnArchivedPaperGoesBackAndForth() {
        var data = data
        let block = TimeBlock(kind: .writing, start: Day(now), end: Day(now).adding(9))
        data.papers[0].blocks = [block]
        let paper = data.papers[0].id
        data.delete([block.id], now: now)
        data.archive(paper, now: now)
        let recovery = data.recover([block.id])
        #expect(data.archive.first?.blocks == [block])
        // Its undo finds it in the Archive.
        #expect(data.putBack(recovery, now: now) == [block.id])
        #expect(data.archive.first?.blocks.isEmpty == true && data.deletedParts.map(\.id) == [block.id])
    }

    @Test func aHandEditedPlaceCannotGoOutOfBounds() throws {
        let paper = UUID()
        let json = """
            {"deletedParts": [{"todo": {"title": "T"}, "paperID": "\(paper)", "index": -3}],
             "papers": [{"id": "\(paper)", "title": "First"}]}
            """
        var loaded = try UserDataStore.decode(Data(json.utf8)).data
        #expect(loaded.deletedParts.first?.index == 0)
        loaded.recover(loaded.deletedParts.map(\.id))
        #expect(loaded.papers[0].todos.map(\.title) == ["T"])
        // Never more days left than Recently Deleted keeps.
        let early = DeletedPaper(paper: Paper(title: "P"), deletedAt: now.addingTimeInterval(30))
        #expect(early.daysLeft(now: now) == 30)
    }

    @Test func aBlockComesBackWithoutThoseWhoLeftAndIntoTheArchive() {
        var data = data
        let sam = Person(name: "Sam", email: "sam@example.org")
        data.mail.groups[1].people = [sam]
        let block = TimeBlock(kind: .review, start: Day(now), end: Day(now).adding(3), people: [sam.id, UUID()])
        data.papers[0].blocks = [block]
        let paper = data.papers[0].id
        data.delete([block.id], now: now)
        data.archive(paper, now: now)
        data.recover([block.id])
        #expect(data.archive.first?.blocks.map(\.people) == [[sam.id]])
    }

    @Test func aGroupKeepsTheSymbolItsItemsAreShownWith() throws {
        var data = UserData(groups: [ItemGroup(name: "Reviews")])
        let item = Paper(title: "JCC", groupID: data.groups[0].id, createdAt: now)
        data.papers = [Paper(title: "P", createdAt: now), item]
        #expect(data.symbol(of: data.papers[0]) == "doc.text" && data.symbol(of: item) == "calendar")
        data.groups[0].symbol = "magnifyingglass"
        #expect(data.symbol(of: item) == "magnifyingglass")
        let again = try UserDataStore.decode(UserDataStore.encode(data))
        #expect(again.issues.isEmpty && again.data == data)
        // One this build does not offer is shown as a calendar; a deleted group's still counts.
        data.groups[0].symbol = "sparkles"
        #expect(data.symbol(of: item) == "calendar")
        let group = data.groups.removeFirst()
        #expect(data.symbol(of: item, deletedWith: ItemGroup(id: group.id, name: "R", symbol: "book")) == "book")
    }

    @Test func theArchiveKeepsEverythingUntilMovedBack() throws {
        var data = data
        let item = data.papers[2]
        let index = data.archive(item.id, now: now)
        #expect(index == 2)
        #expect(data.items(in: group.id).isEmpty)
        #expect(data.archive.first?.archivedAt == now)
        #expect(data.archive.first?.deadlines == item.deadlines)
        // Deleted from the Archive, it goes back there when recovered.
        data.delete([item.id], now: now)
        data.recover([item.id])
        #expect(data.archive.map(\.id) == [item.id])
        data.unarchive(item.id, at: 0)
        #expect(data.papers.first?.id == item.id && data.papers.first?.archivedAt == nil)
        let again = try UserDataStore.decode(UserDataStore.encode(data)).data
        #expect(again == data)
    }
}

@Suite struct GroupOrderTests {
    let applications = ItemGroup(name: "Applications")
    let reviews = ItemGroup(name: "Reviews")
    var data: UserData {
        UserData(
            papers: [
                Paper(title: "P1"), Paper(title: "A1", groupID: applications.id), Paper(title: "P2"),
                Paper(title: "R1", groupID: reviews.id), Paper(title: "A2", groupID: applications.id),
            ],
            groups: [applications, reviews])
    }

    /// The rows as `heading` names and item titles.
    func names(_ rows: [SidebarRow], in data: UserData) -> [String] {
        rows.map { row in
            switch row {
            case let .heading(id): "#" + (data.groups.first { $0.id == id }?.name ?? "Papers")
            case let .item(id): data.papers.first { $0.id == id }?.title ?? "?"
            }
        }
    }

    @Test func thePapersCanComeAnywhereAmongTheGroups() {
        var data = data
        #expect(data.groupOrder == [nil, applications.id, reviews.id])
        data.groupOrder = [applications.id, nil, reviews.id]
        #expect(data.papersPosition == 1 && data.groups == [applications, reviews])
        data.groupOrder = [reviews.id, applications.id]
        #expect(data.groupOrder == [reviews.id, nil, applications.id])
        // A group taken out and put back returns to its place, and the papers keep theirs.
        let removed = data.removeGroup(reviews.id)
        #expect(removed?.position == 0 && data.groupOrder == [nil, applications.id])
        data.insertGroup(reviews, at: 0)
        #expect(data.groupOrder == [reviews.id, nil, applications.id])
    }

    @Test func theSidebarShowsEachGroupWithItsItems() {
        let data = data
        #expect(
            names(data.sidebarRows, in: data) == ["#Papers", "P1", "P2", "#Applications", "A1", "A2", "#Reviews", "R1"])
    }

    @Test func anItemJoinsTheGroupItIsDroppedIn() {
        var data = data
        let rows = data.sidebarRows
        // P2 dropped between A1 and A2 becomes an item of Applications.
        data.arrange(rows.moving(fromOffsets: [2], toOffset: 5))
        #expect(
            names(data.sidebarRows, in: data) == ["#Papers", "P1", "#Applications", "A1", "P2", "A2", "#Reviews", "R1"])
        #expect(data.papers.first { $0.title == "P2" }?.groupID == applications.id)
        // Dropped above every heading, it is the first of the first group.
        data.arrange(data.sidebarRows.moving(fromOffsets: [7], toOffset: 0))
        #expect(names(data.sidebarRows, in: data).prefix(3) == ["#Papers", "R1", "P1"])
        #expect(data.papers.first { $0.title == "R1" }?.isPaper == true)
    }

    @Test func aHeadingTakesItsItemsToTheNearestPlaceBetweenGroups() {
        var data = data
        let rows = data.sidebarRows
        #expect(
            names(rows.moving(fromOffsets: [6], toOffset: 0), in: data)
                == ["#Reviews", "R1", "#Papers", "P1", "P2", "#Applications", "A1", "A2"])
        #expect(
            names(rows.moving(fromOffsets: [0], toOffset: 8), in: data)
                == ["#Applications", "A1", "A2", "#Reviews", "R1", "#Papers", "P1", "P2"])
        // Dropped just below a heading, it goes above that group; dropped near a group's end, below.
        #expect(
            names(rows.moving(fromOffsets: [6], toOffset: 4), in: data)
                == ["#Papers", "P1", "P2", "#Reviews", "R1", "#Applications", "A1", "A2"])
        #expect(
            names(rows.moving(fromOffsets: [6], toOffset: 2), in: data)
                == ["#Papers", "P1", "P2", "#Reviews", "R1", "#Applications", "A1", "A2"])
        // Halfway into a group, it goes the way it was dragged.
        #expect(rows.moving(fromOffsets: [0], toOffset: 7) == rows.moving(fromOffsets: [0], toOffset: 8))
        var short = data
        short.papers.removeAll { $0.title == "A2" }
        #expect(
            names(short.sidebarRows.moving(fromOffsets: [5], toOffset: 4), in: short)
                == ["#Papers", "P1", "P2", "#Reviews", "R1", "#Applications", "A1"])
        // Dropped within itself, nothing moves.
        #expect(rows.moving(fromOffsets: [3], toOffset: 5) == rows)
        #expect(rows.moving(fromOffsets: [3], toOffset: 6) == rows)
        data.arrange(rows.moving(fromOffsets: [0], toOffset: 8))
        #expect(data.groupOrder == [applications.id, reviews.id, nil])
        #expect(data.items(in: nil).map(\.title) == ["P1", "P2"])
    }

    @Test func aRowDraggedAmongThoseShownLeavesTheOthersInPlace() throws {
        let data = data
        let rows = data.sidebarRows
        // A2 is not shown, as a finished item is not in the menu bar window.
        let shown = rows.filter { $0 != rows[5] }
        guard case let .item(p1) = rows[1] else { throw CancellationError() }
        #expect(
            names(rows.moving(item: p1, to: 4, among: shown), in: data)
                == ["#Papers", "P2", "#Applications", "A1", "P1", "A2", "#Reviews", "R1"])
        #expect(rows.moving(item: p1, to: 0, among: shown) == rows)
    }

    @Test func arrangingKeepsWhatItDoesNotKnow() {
        var data = data
        let rows = data.sidebarRows
        let added = Paper(title: "New")
        data.papers.append(added)
        let gone = data.papers.first { $0.title == "A1" }!.id
        data.papers.removeAll { $0.id == gone }
        data.arrange(rows.moving(fromOffsets: [1], toOffset: 3))
        #expect(
            names(data.sidebarRows, in: data) == [
                "#Papers", "P2", "P1", "New", "#Applications", "A2", "#Reviews", "R1",
            ])
        // The heading of a group deleted since lets its items go to the papers.
        let order = data.sidebarRows
        data.removeGroup(reviews.id)
        data.arrange(order)
        #expect(data.papers.first { $0.title == "R1" }?.isPaper == true)
        #expect(data.groupOrder == [nil, applications.id])
    }
}

@Suite struct DeadlineListTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func deadline(_ title: String, inDays days: Double) -> CustomDeadline {
        CustomDeadline(title: title, date: now.addingTimeInterval(days * 86_400))
    }

    @Test func theFirstDeadlineWithoutAConferenceIsTheMainOne() {
        let item = Paper(title: "Fellowship", groupID: UUID())
        var data = UserData(papers: [item])
        let letters = deadline("Letters", inDays: 5)
        data.addDeadline(letters, to: item.id, now: now)
        data.addDeadline(deadline("Interview", inDays: 40), to: item.id, now: now)
        #expect(data.papers[0].mainDeadline == letters.id && data.papers[0].deadlines.count == 2)
        // With a conference, the paper submission stays the main one.
        var paper = Paper(title: "P", target: Paper.Target(series: "AI/cvpr", year: 2027))
        data.papers.append(paper)
        data.addDeadline(deadline("Supplementary", inDays: 7), to: paper.id, now: now)
        paper = data.papers[1]
        #expect(paper.mainDeadline == nil)
    }

    @Test func aDeadlineAddedToASubmittedPaperIsNotTheOneItWentInBy() {
        var data = UserData(papers: [Paper(title: "P", stage: .submitted)])
        data.addDeadline(deadline("Camera-ready", inDays: 20), to: data.papers[0].id, now: now)
        #expect(data.papers[0].mainDeadline == nil)
        let deadlines = PaperDeadlines.resolve(data.papers[0], catalog: .empty, now: now)
        #expect(deadlines.flag?.title == "Camera-ready" && deadlines.flag?.isDone == false)
        #expect(deadlines.next(after: now)?.title == "Camera-ready")
        // One that has passed is the one it went in by.
        let workshop = deadline("Workshop", inDays: -5)
        data.addDeadline(workshop, to: data.papers[0].id, now: now)
        #expect(data.papers[0].mainDeadline == workshop.id)
    }

    @Test func deletingTheMainOneHandsOverToTheNextOwn() {
        let passed = deadline("Abstract", inDays: -3)
        let main = deadline("Application", inDays: 10)
        let later = deadline("Interview", inDays: 40)
        var data = UserData(papers: [
            Paper(title: "I", deadlines: [passed, main, later], mainDeadline: main.id, groupID: UUID())
        ])
        data.delete([main.id], now: now)
        #expect(data.papers[0].mainDeadline == later.id)
        data.delete([later.id], now: now)
        // None ahead: the last.
        #expect(data.papers[0].mainDeadline == passed.id)
        data.delete([passed.id], now: now)
        #expect(data.papers[0].mainDeadline == nil)
        // Recovered, the one it aimed at is aimed at again.
        data.recover([main.id])
        #expect(data.papers[0].mainDeadline == main.id)
    }

    @Test func aSubmittedPaperAimsOnlyAtWhatItWentInBy() {
        let workshop = deadline("Workshop", inDays: -5)
        let cameraReady = deadline("Camera-ready", inDays: 20)
        var data = UserData(papers: [
            Paper(title: "P", deadlines: [workshop, cameraReady], mainDeadline: workshop.id, stage: .submitted)
        ])
        data.delete([workshop.id], now: now)
        // The camera-ready is not taken for the deadline it was submitted by, and stays open.
        #expect(data.papers[0].mainDeadline == nil)
        let deadlines = PaperDeadlines.resolve(data.papers[0], catalog: .empty, now: now)
        #expect(deadlines.flag?.title == "Camera-ready" && deadlines.flag?.isDone == false)
    }

    @Test func aTickFromBeforeItWasTheMainOneIsNotASubmission() {
        var registration = deadline("Registration", inDays: 4)
        registration.isDone = true
        let paper = Paper(title: "P", deadlines: [registration], mainDeadline: registration.id, stage: .writing)
        let deadlines = PaperDeadlines.resolve(paper, catalog: .empty, now: now)
        #expect(deadlines.main?.isDone == false && deadlines.flag?.title == "Registration")
        // An item's main deadline is ticked off by itself.
        var item = paper
        item.groupID = UUID()
        #expect(PaperDeadlines.resolve(item, catalog: .empty, now: now).main?.isDone == true)
    }

    @Test func makingAnOwnDeadlineTheMainOne() {
        let a = deadline("A", inDays: 3)
        let b = deadline("B", inDays: 9)
        var data = UserData(papers: [Paper(title: "P", deadlines: [a, b], mainDeadline: a.id)])
        data.makeMainDeadline(b.id, of: data.papers[0].id)
        #expect(data.papers[0].mainDeadline == b.id)
        let deadlines = PaperDeadlines.resolve(data.papers[0], catalog: .empty, now: now)
        #expect(deadlines.main?.title == "B" && deadlines.canChooseMain)
        // A submitted paper no longer chooses: it has gone in.
        data.papers[0].stage = .submitted
        #expect(!PaperDeadlines.resolve(data.papers[0], catalog: .empty, now: now).canChooseMain)
    }

    @Test func removingTheConferenceAimsAtTheNextOwn() {
        let workshop = deadline("Workshop", inDays: 12)
        var paper = Paper(title: "P", target: Paper.Target(series: "AI/cvpr", year: 2027), deadlines: [workshop])
        paper.doneDeadlines = ["cvpr27|abstract|#1"]
        var data = UserData(papers: [paper])
        data.removeConference(of: paper.id, now: now)
        #expect(data.papers[0].target == nil && data.papers[0].mainDeadline == workshop.id)
        #expect(data.papers[0].doneDeadlines.isEmpty)
    }

    @Test func ticksStayInOrder() {
        var data = UserData(papers: [Paper(title: "P", target: Paper.Target(series: "AI/cvpr", year: 2027))])
        func tick(_ id: String, _ isDone: Bool = true) {
            data.setDone(
                isDone,
                of: PaperDeadline(
                    id: id, source: .conference(.abstract), value: DeadlineValue(raw: "", date: nil), timeZone: "AoE"),
                in: data.papers[0].id)
        }
        tick("b|abstract|#1")
        tick("a|abstract|#1")
        #expect(data.papers[0].doneDeadlines == ["a|abstract|#1", "b|abstract|#1"])
        tick("a|abstract|#1", false)
        #expect(data.papers[0].doneDeadlines == ["b|abstract|#1"])
    }

    @Test func movingADeadlineKeepsItsTimeAcrossDaylightSaving() {
        // 23:59 Pacific time on Oct 31, a day before the clocks go back.
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let halloween = date("2026-10-31 23:59", pacific)
        let moved = CustomDeadline(title: "X", date: halloween, timeZone: "PT").moved(byDays: 7)
        #expect(moved.date == date("2026-11-07 23:59", pacific))
        #expect(moved.date.timeIntervalSince(halloween) == 7 * 86_400 + 3600)
    }
}
