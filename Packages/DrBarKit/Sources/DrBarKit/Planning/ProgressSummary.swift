import Foundation

/// The words of the progress email and its image, in the language chosen for its recipients.
///
/// Separate from the app's own localization: the email language is a setting, not the UI language.
public struct MailStrings: Sendable {
    public let language: MailLanguage

    public init(_ language: MailLanguage) {
        self.language = language
    }

    public var today: String { pick("Today", "今天") }
    public var milestones: String { pick("Milestones", "里程碑") }
    public var deadlines: String { pick("Deadlines", "截止日期") }
    var target: String { pick("Target:", "目标：") }
    var done: String { pick("Done:", "已完成：") }
    var now: String { pick("Now:", "进行中：") }
    var next: String { pick("Next:", "下一步：") }
    var due: String { pick("Due:", "里程碑：") }
    var abstractDeadline: String { pick("abstract deadline", "摘要截止") }
    var paperDeadline: String { pick("paper deadline", "全文截止") }
    var deadline: String { pick("deadline", "截止") }
    var notAnnounced: String { pick("deadline not announced yet", "截止日期尚未公布") }
    var submitted: String { pick("submitted", "已投稿") }
    var decided: String { pick("decided", "已出结果") }
    var rebuttal: String { pick("rebuttal", "Rebuttal") }
    var decision: String { pick("decision", "结果通知") }

    // The first line of an update and the banner of its image.

    func underWayWithYou(_ name: String, until end: String) -> String {
        pick("\(name) with you is under way, until \(end).", "与您一起的\(name)正在进行，到 \(end) 结束。")
    }

    func startsWithYou(_ name: String, on day: String) -> String {
        pick("\(name) with you starts on \(day).", "与您一起的\(name)将于 \(day) 开始。")
    }

    func behind(_ what: String) -> String {
        pick("Behind schedule: \(what).", "进度落后：\(what)。")
    }

    func plannedToEnd(_ name: String, _ day: String) -> String {
        pick("\(name) was planned to end on \(day)", "\(name)原定 \(day) 完成")
    }

    func wasDue(_ name: String, _ day: String) -> String {
        pick("\(name) was due on \(day)", "\(name)原定 \(day) 到期")
    }

    var pastDeadline: String { pick("The plan runs past the deadline.", "计划排到了截止日期之后。") }

    func onTrack(_ name: String, until end: String) -> String {
        pick("On track: \(name) until \(end).", "进度正常：\(name)进行到 \(end)。")
    }

    var onTrackAlone: String { pick("On track.", "进度正常。") }

    // The other work the recipients may hear about.

    /// What it is headed with, in the email and its image.
    public var alsoWorkingOn: String { pick("Also working on", "同时在做") }

    func until(_ name: String, _ day: String) -> String {
        pick("\(name) until \(day)", "\(spaced(name))进行到 \(day)")
    }

    func from(_ name: String, _ day: String) -> String {
        pick("\(name) from \(day)", "\(spaced(name))将于 \(day) 开始")
    }

    /// A Latin name with a space before the Chinese that follows it.
    private func spaced(_ name: String) -> String {
        name.last?.isASCII == true ? name + " " : name
    }

    func since(_ day: String, _ changes: [String]) -> String {
        pick("Since \(day): \(changes.joined(separator: ", ")).", "自 \(day) 以来：\(changes.joined(separator: "，"))。")
    }

    func finished(_ name: String) -> String { pick("\(name) done", "\(name)已完成") }
    func started(_ name: String) -> String { pick("\(name) started", "\(name)已开始") }

    /// What the banner's chip says about the plan.
    public func status(_ status: PlanStatus) -> String {
        switch status {
        case .onTrack: pick("On track", "进度正常")
        case .behind: pick("Behind schedule", "进度落后")
        case .conflict: pick("Past the deadline", "超出截止日期")
        case .noPlan: pick("Not planned yet", "尚未计划")
        }
    }

    /// "40% of the plan done"
    public func progress(_ fraction: Double) -> String {
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)).locale(language.locale))
        return pick("\(percent) of the plan done", "计划已完成 \(percent)")
    }

    /// "Now: Internal review · 31 Oct – 7 Nov · with Jane Doe", or what comes next.
    public func stageLine(_ block: TimeBlock, isNow: Bool, people: [UUID: Person]) -> String {
        let range =
            "\(ProgressSummary.formatDay(block.start, language)) – \(ProgressSummary.formatDay(block.end, language))"
        var parts = [blockName(block), range]
        let names = block.people.compactMap { people[$0]?.displayName }
        if !names.isEmpty {
            parts.append(pick("with ", "与 ") + names.formatted(.list(type: .and).locale(language.locale)))
        }
        return (isNow ? now : next) + (language == .english ? " " : "") + parts.joined(separator: " · ")
    }

    /// The unit under the banner's big number: "days", "天".
    public func days(_ count: Int) -> String {
        pick(count == 1 ? "day" : "days", "天")
    }

    /// The subject of the first email of a thread.
    public func defaultSubject(paperTitle: String) -> String {
        pick("Progress: \(paperTitle)", "论文进展：\(paperTitle)")
    }

    /// "CVPR 2027 paper deadline", "CVPR 2027 全文截止", or an own deadline's name as it was typed;
    /// without `conference`, just "paper deadline".
    public func name(of deadline: PaperDeadline, conference: PaperDeadlines.Conference? = nil) -> String {
        guard let kind = deadline.kind else {
            let title = deadline.title.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? self.deadline : title
        }
        let what =
            switch kind {
            case .abstract: abstractDeadline
            case .paper: paperDeadline
            case .rebuttal: rebuttal
            case .decision: decision
            }
        return named(conference?.fullTitle ?? "", what)
    }

    /// What the image writes beside a deadline's flag: "Abstract deadline", "Rebuttal", an own
    /// deadline's name as it was typed, or, with `conference` for the marked one, the venue too:
    /// "CVPR 2027 paper deadline".
    public func label(of deadline: PaperDeadline, conference: PaperDeadlines.Conference? = nil) -> String {
        let name = name(of: deadline, conference: conference)
        let isTyped = deadline.kind == nil && !deadline.title.trimmingCharacters(in: .whitespaces).isEmpty
        guard language == .english, !isTyped, let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    /// "34 days to the CVPR 2027 paper deadline", "距 CVPR 2027 全文截止还有 34 天", or "5 days to
    /// Camera-ready" for a deadline that goes by the name it was given.
    func timeLeft(days: Int, what: String, isNamed: Bool = false) -> String {
        switch language {
        case .english:
            let amount = days < 1 ? "less than a day" : days == 1 ? "1 day" : "\(days) days"
            return "\(amount) to \(isNamed ? "" : "the ")\(what)"
        case .chinese:
            // A space where a Latin name meets Chinese, on either side.
            let lead = what.first?.isASCII == true ? "距 " : "距"
            let trail = what.last?.isASCII == true ? " " : ""
            return days < 1 ? "\(lead)\(what)\(trail)不到 1 天" : "\(lead)\(what)\(trail)还有 \(days) 天"
        }
    }

    /// "25 Oct – 7 Nov, with Sam Lee and Mia Chen"
    func with(_ range: String, _ names: [String]) -> String {
        let list = names.formatted(.list(type: .and).locale(language.locale))
        return pick("\(range), with \(list)", "\(range)，与 \(list)")
    }

    /// "CVPR 2027 paper deadline", or just "paper deadline" without a conference.
    func named(_ name: String, _ kind: String) -> String {
        name.isEmpty ? kind : "\(name) \(kind)"
    }

    /// A block's name, as the app shows it, in the email's language.
    public func blockName(_ block: TimeBlock) -> String {
        guard block.kind == .custom else { return kindName(block.kind) }
        let name = block.customName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? pick("Untitled block", "未命名时间块") : name
    }

    func milestoneName(_ milestone: Milestone) -> String {
        let name = milestone.title.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? pick("Untitled milestone", "未命名里程碑") : name
    }

    func kindName(_ kind: TimeBlock.Kind) -> String {
        switch kind {
        case .experiments: pick("Experiments", "实验")
        case .writing: pick("Writing", "写作")
        case .review: pick("Internal review", "内审修改")
        case .buffer: pick("Buffer", "缓冲")
        case .custom: pick("Other", "其他")
        }
    }

    public var noBlocks: String { pick("No time blocks planned yet.", "还没有安排时间块。") }

    private func pick(_ english: String, _ chinese: String) -> String {
        language == .english ? english : chinese
    }
}

/// Builds the plain-text progress summary from a paper's deadlines and blocks:
///
///     Target: CVPR 2027 — abstract deadline 10 Nov, 23:59 · paper deadline 16 Nov, 23:59 (UTC-12)
///     Done: Experiments (12 Oct – 24 Oct)
///     Now: Writing (25 Oct – 7 Nov)
///     Next: Internal review (8 Nov – 14 Nov)
///     Due: Full draft to Jane (1 Nov)
///
/// Deadlines are written in the conference's own time zone, because the recipients' is unknown.
extension Paper {
    /// Its blocks as an update shows them: without the buffers, for a group that does not see them.
    public func blocksForUpdate(hidingBuffers: Bool) -> [TimeBlock] {
        hidingBuffers ? blocks.filter { $0.kind != .buffer } : blocks
    }
}

public enum ProgressSummary {
    /// The block an update names as under way: the first in progress of those it shows.
    public static func currentBlock(of paper: Paper, hidesBufferBlocks: Bool, today: Day) -> TimeBlock? {
        PlanMath.blocksInProgress(paper.blocksForUpdate(hidingBuffers: hidesBufferBlocks), today: today).first
    }

    /// - Parameter people: the people of the recipient groups, whom blocks name as working on them.
    public static func text(
        paper: Paper, deadlines: PaperDeadlines, language: MailLanguage, hidesBufferBlocks: Bool,
        people: [UUID: Person] = [:], now: Date, calendar: Calendar = .gregorianLocal
    ) -> String {
        let strings = MailStrings(language)
        let today = Day(now, calendar: calendar)
        let blocks = paper.blocksForUpdate(hidingBuffers: hidesBufferBlocks)
        var lines: [String] = []

        if let target = targetText(deadlines, paper: paper, now: now, strings: strings) {
            lines.append(line(strings.target, target, language))
        }
        if let done = PlanMath.lastFinishedBlock(blocks) {
            lines.append(line(strings.done, describe(done, strings, people), language))
        }
        let current = PlanMath.blocksInProgress(blocks, today: today)
        if !current.isEmpty {
            lines.append(
                line(strings.now, current.map { describe($0, strings, people) }.joined(separator: " + "), language))
        }
        if let next = PlanMath.upcomingBlocks(blocks, today: today).first {
            lines.append(line(strings.next, describe(next, strings, people), language))
        }
        if let milestone = PlanMath.nextMilestone(paper.milestones, today: today) {
            let day = parenthesized(formatDay(milestone.day, strings.language), language)
            lines.append(line(strings.due, strings.milestoneName(milestone) + day, language))
        }
        return lines.joined(separator: "\n")
    }

    /// The first line of an update, which the inbox shows before it is opened: what the recipients
    /// take part in while it is under way or about to start, how the plan stands when it is not on
    /// track, and what has changed since the last update.
    ///
    /// - Parameters:
    ///   - recipients: the ids of the people the email goes to, to say "with you" on their blocks.
    ///   - lastUpdate: when the thread last had an update, to say what has changed since.
    public static func headline(
        paper: Paper, status: PlanStatus, recipients: Set<UUID>, lastUpdate: Date?, language: MailLanguage,
        hidesBufferBlocks: Bool, now: Date, calendar: Calendar = .gregorianLocal
    ) -> String {
        let strings = MailStrings(language)
        let today = Day(now, calendar: calendar)
        let blocks = paper.blocksForUpdate(hidingBuffers: hidesBufferBlocks)
        func day(_ day: Day) -> String { formatDay(day, language) }
        var sentences: [String] = []
        var named: Set<UUID> = []

        let theirs = blocks.filter { !$0.isDone && !recipients.isDisjoint(with: $0.people) }.sorted {
            $0.start < $1.start
        }
        if let block = theirs.first(where: { $0.contains(today) }) {
            sentences.append(strings.underWayWithYou(strings.blockName(block), until: day(block.end)))
            named.insert(block.id)
        } else if let block = theirs.first(where: { $0.start > today && today.days(to: $0.start) <= 14 }) {
            sentences.append(strings.startsWithYou(strings.blockName(block), on: day(block.start)))
            named.insert(block.id)
        }

        switch status {
        case .behind:
            if let late = blocks.filter({ $0.isOverdue(today: today) }).max(by: { $0.end < $1.end }) {
                sentences.append(strings.behind(strings.plannedToEnd(strings.blockName(late), day(late.end))))
                named.insert(late.id)
            } else if let late = paper.milestones.filter({ $0.isOverdue(today: today) }).max(by: { $0.day < $1.day }) {
                sentences.append(strings.behind(strings.wasDue(strings.milestoneName(late), day(late.day))))
            }
        case .conflict:
            sentences.append(strings.pastDeadline)
        case .onTrack where sentences.isEmpty:
            if let current = PlanMath.blocksInProgress(blocks, today: today).first {
                sentences.append(strings.onTrack(strings.blockName(current), until: day(current.end)))
                named.insert(current.id)
            } else {
                sentences.append(strings.onTrackAlone)
            }
        case .noPlan:
            sentences.append(strings.noBlocks)
        case .onTrack:
            break
        }

        if let lastUpdate {
            let since = Day(lastUpdate, calendar: calendar)
            let finished = blocks.filter { $0.isDone && $0.end >= since && !named.contains($0.id) }
            let started = blocks.filter {
                !$0.isDone && $0.start > since && $0.start <= today && !named.contains($0.id)
            }
            let changes =
                finished.map { strings.finished(strings.blockName($0)) }
                + started.map { strings.started(strings.blockName($0)) }
            if !changes.isEmpty {
                sentences.append(strings.since(day(since), changes))
            }
        }
        return sentences.joined(separator: language == .english ? " " : "")
    }

    /// The email body: the first line that says what it is about, the user's message, the summary,
    /// the other work and the signature, separated by blank lines.
    public static func body(
        headline: String = "", message: String, summary: String?, otherWork: String? = nil, signature: String
    ) -> String {
        [headline, message, summary ?? "", otherWork ?? "", signature]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// "Also working on:" and a line for each of `work`: the title with its conference, the block
    /// under way or the next one, or the stage once submitted, and the next deadline on its day in
    /// its own time zone. Nothing else of them goes out: neither their notes, to-dos and
    /// milestones, nor the people on their blocks.
    public static func otherWork(
        _ work: [(paper: Paper, deadlines: PaperDeadlines)], language: MailLanguage, hidesBufferBlocks: Bool,
        now: Date, calendar: Calendar = .gregorianLocal
    ) -> String? {
        guard !work.isEmpty else { return nil }
        let strings = MailStrings(language)
        let today = Day(now, calendar: calendar)
        let lines = work.map { paper, deadlines in
            let blocks = paper.blocksForUpdate(hidingBuffers: hidesBufferBlocks)
            var parts: [String] = []
            if let current = PlanMath.blocksInProgress(blocks, today: today).first {
                parts.append(strings.until(strings.blockName(current), formatDay(current.end, language)))
            } else if let next = PlanMath.upcomingBlocks(blocks, today: today).first {
                parts.append(strings.from(strings.blockName(next), formatDay(next.start, language)))
            } else if paper.isPaper, paper.stage.isSubmitted {
                parts.append(paper.stage == .decided ? strings.decided : strings.submitted)
            }
            if let next = deadlines.next(after: now), let date = next.date {
                let zone = DeadlineTimeZone.custom(next.timeZone) ?? calendar.timeZone
                parts.append("\(strings.name(of: next)) \(formatDay(date, in: zone, language))")
            }
            let title =
                paper.title.trimmingCharacters(in: .whitespaces)
                + (deadlines.conference.map { parenthesized($0.fullTitle, language) } ?? "")
            return parts.isEmpty ? title : "\(title) — \(parts.joined(separator: " · "))"
        }
        return ([strings.alsoWorkingOn + (language == .english ? ":" : "：")] + lines).joined(separator: "\n")
    }

    /// The deadline ahead that comes next and is not done, what to call it, and whether that is a
    /// name of its own.
    static func nextDate(
        _ deadlines: PaperDeadlines, now: Date, strings: MailStrings
    ) -> (what: String, isNamed: Bool, date: Date)? {
        guard let next = deadlines.next(after: now), let date = next.date else { return nil }
        let isNamed = next.kind == nil && !next.title.trimmingCharacters(in: .whitespaces).isEmpty
        return (strings.name(of: next, conference: deadlines.conference), isNamed, date)
    }

    /// The banner's big number and what it counts down to: (12, "days", "to the CVPR 2027 paper
    /// deadline"). Days are rounded down, as in the subject.
    public static func countdown(
        _ deadlines: PaperDeadlines, language: MailLanguage, now: Date
    ) -> (days: Int, unit: String, caption: String)? {
        let strings = MailStrings(language)
        guard let next = nextDate(deadlines, now: now, strings: strings) else { return nil }
        let days = Int(next.date.timeIntervalSince(now) / 86_400)
        let caption =
            language == .english
            ? "to \(next.isNamed ? "" : "the ")\(next.what)"
            : (next.what.first?.isASCII == true ? "距 " : "距") + next.what
        return (days, strings.days(days), caption)
    }

    /// What every update adds to the thread's subject, so the stage and the time left show in the
    /// inbox: " (Writing · 34 days to the CVPR 2027 paper deadline)", or "" when there is neither.
    /// Days are rounded down, so it never reads as more time than there is.
    public static func subjectSuffix(
        _ deadlines: PaperDeadlines, current: TimeBlock? = nil, language: MailLanguage, now: Date
    ) -> String {
        let strings = MailStrings(language)
        var parts: [String] = []
        if let current {
            parts.append(strings.blockName(current))
        }
        if let next = nextDate(deadlines, now: now, strings: strings) {
            let days = Int(next.date.timeIntervalSince(now) / 86_400)
            parts.append(strings.timeLeft(days: days, what: next.what, isNamed: next.isNamed))
        }
        return parts.isEmpty ? "" : parenthesized(parts.joined(separator: " · "), language)
    }

    /// "Re: <subject>", the subject of every later update in a thread.
    public static func replySubject(_ subject: String) -> String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }

    static func line(_ label: String, _ value: String, _ language: MailLanguage) -> String {
        language == .english ? "\(label) \(value)" : label + value
    }

    /// "CVPR 2027 — abstract deadline 10 Nov, 23:59 · paper deadline 16 Nov, 23:59 (UTC-12)": what
    /// is due from the next deadline up to the one it aims at. Once it is submitted, "CVPR 2027 —
    /// submitted · rebuttal 2 Feb, 23:59 (UTC-12)", and once decided, "decided" and what follows.
    static func targetText(_ deadlines: PaperDeadlines, paper: Paper, now: Date, strings: MailStrings) -> String? {
        func titled(_ text: String) -> String {
            deadlines.conference.map { "\($0.fullTitle) — \(text)" } ?? text
        }
        if paper.stage.isSubmitted {
            let stage = paper.stage == .decided ? strings.decided : strings.submitted
            return titled(deadlines.flag.map { "\(stage) · \(dated([$0], strings))" } ?? stage)
        }
        guard let main = deadlines.main else {
            return deadlines.conference == nil ? nil : titled(strings.notAnnounced)
        }
        guard let mainDate = main.date else { return titled(strings.notAnnounced) }
        let due = deadlines.upcoming(after: now).filter { deadline in deadline.date.map { $0 <= mainDate } ?? false }
        return titled(dated(due.isEmpty ? [main] : due, strings))
    }

    /// "abstract deadline 10 Nov, 23:59 · paper deadline 16 Nov, 23:59 (UTC-12)": each in its own
    /// time zone, as the call for papers gives it, written once after those that share it.
    static func dated(_ deadlines: [PaperDeadline], _ strings: MailStrings) -> String {
        deadlines.indices.map { index in
            let deadline = deadlines[index]
            let name = strings.name(of: deadline)
            guard let date = deadline.date, let zone = DeadlineTimeZone.custom(deadline.timeZone) else { return name }
            let when = "\(name) \(formatDeadline(date, in: zone, language: strings.language))"
            // Local time is written as its offset on the day, which daylight saving can change.
            let notation = DeadlineTimeZone.notation(deadline.timeZone, at: date)
            let next = deadlines.indices.contains(index + 1) ? deadlines[index + 1] : nil
            let nextNotation = next.flatMap { next in next.date.map { DeadlineTimeZone.notation(next.timeZone, at: $0) }
            }
            return nextNotation == notation ? when : when + parenthesized(notation, strings.language)
        }.joined(separator: " · ")
    }

    /// "Writing (25 Oct – 7 Nov, with Sam Lee)"
    static func describe(_ block: TimeBlock, _ strings: MailStrings, _ people: [UUID: Person] = [:]) -> String {
        let range = "\(formatDay(block.start, strings.language)) – \(formatDay(block.end, strings.language))"
        let names = block.people.compactMap { people[$0]?.displayName }
        let details = names.isEmpty ? range : strings.with(range, names)
        return strings.blockName(block) + parenthesized(details, strings.language)
    }

    static func parenthesized(_ text: String, _ language: MailLanguage) -> String {
        language == .english ? " (\(text))" : "（\(text)）"
    }

    /// "16 Nov, 23:59" or "11月16日 23:59", in the deadline's own time zone.
    static func formatDeadline(_ date: Date, in zone: TimeZone, language: MailLanguage) -> String {
        let base = Date.FormatStyle(locale: language.locale, calendar: Calendar(identifier: .gregorian), timeZone: zone)
        let day = date.formatted(base.day().month(.abbreviated))
        let time = date.formatted(base.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return language == .english ? "\(day), \(time)" : "\(day) \(time)"
    }

    /// "16 Nov" or "11月16日": the day of `date` where it is given.
    static func formatDay(_ date: Date, in zone: TimeZone, _ language: MailLanguage) -> String {
        let style = Date.FormatStyle(locale: language.locale, calendar: .gregorian(in: zone), timeZone: zone)
        return date.formatted(style.day().month(.abbreviated))
    }

    /// "12 Oct" or "10月12日". Days carry no time zone, so they are formatted in UTC.
    static func formatDay(_ day: Day, _ language: MailLanguage) -> String {
        let calendar = Calendar.gregorian(in: .gmt)
        let style = Date.FormatStyle(locale: language.locale, calendar: calendar, timeZone: .gmt)
        return day.startDate(calendar: calendar).formatted(style.day().month(.abbreviated))
    }
}
