import Foundation

/// Builds deadline list rows from the catalog.
public enum DeadlineRows {
    /// The rows of what `following` covers, in display order: dated rows by deadline (so bars grow
    /// like a staircase), then rows whose deadline is not announced, then rows whose date cannot be
    /// read.
    ///
    /// Dated rows are included while their deadline is ahead, or passed since `recentSince`, so
    /// a list can show what just happened.
    public static func build(
        catalog: ConferenceCatalog, following: Following, now: Date, recentSince: Date? = nil
    ) -> [DeadlineRow] {
        let since = min(recentSince ?? now, now)
        var scheduled: [DeadlineRow] = []
        var notAnnounced: [DeadlineRow] = []
        var unreadable: [DeadlineRow] = []
        let currentYear = Calendar.gregorian(in: .gmt).component(.year, from: now)

        for series in catalog.series where following.followsAnyEdition(of: series.id) {
            let latestYear = series.editions.map(\.year).max()
            var seriesScheduled: [DeadlineRow] = []
            var seriesNotAnnounced: [DeadlineRow] = []
            var hasUpcoming = false

            for edition in series.editions where following.follows(series: series.id, year: edition.year) {
                for round in edition.rounds {
                    func row(
                        _ state: DeadlineRow.State, abstract: Date? = nil, paper: Date? = nil, raw: String? = nil
                    ) -> DeadlineRow {
                        let source = DeadlineRow.Source.conference(
                            series: series.id, edition: edition.id, round: round.id)
                        return DeadlineRow(
                            id: source.id, source: source, name: series.title, year: edition.year,
                            roundLabel: round.label(roundCount: edition.rounds.count), abstractDate: abstract,
                            paperDate: paper,
                            rebuttalDate: round.rebuttal?.date, decisionDate: round.decision?.date,
                            meeting: edition.meeting, place: edition.shortPlace, flags: edition.flags,
                            state: state, timeZone: edition.timeZone, rawDeadline: raw)
                    }

                    if let paper = round.paper?.date {
                        if paper > since {
                            seriesScheduled.append(row(.scheduled, abstract: round.abstract?.date, paper: paper))
                            hasUpcoming = hasUpcoming || paper > now
                        }
                    } else if round.paper?.isAnnounced != true, let abstract = round.abstract?.date {
                        // Only the abstract deadline is known; the bar ends there.
                        if abstract > since {
                            seriesScheduled.append(row(.scheduled, abstract: abstract))
                            hasUpcoming = hasUpcoming || abstract > now
                        }
                    } else if let value = [round.paper, round.abstract].compactMap({ $0 }).first(where: \.isAnnounced) {
                        // A date is written but could not be read (unknown time zone or a typo).
                        if let naive = naiveDate(value.raw), naive > now.addingTimeInterval(-86_400) {
                            unreadable.append(row(.unreadable, raw: value.raw))
                        }
                    } else if edition.year == latestYear, edition.year >= currentYear, !edition.isOver(now: now) {
                        seriesNotAnnounced.append(row(.notAnnounced))
                    }
                }
            }
            scheduled += seriesScheduled
            // "Not announced" only matters while the series has no dated deadline ahead.
            if !hasUpcoming {
                notAnnounced += seriesNotAnnounced
            }
        }

        scheduled.sort { ($0.endDate!, $0.title) < ($1.endDate!, $1.title) }
        notAnnounced.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        unreadable.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return scheduled + notAnnounced + unreadable
    }

    /// Everything followed that is ahead and not done, once each: every deadline of the papers and
    /// items, and the abstract and paper deadlines of the starred conferences' rounds that no paper
    /// speaks for. A deadline that one paper has open opens that paper; one that several have, or
    /// only a star, opens the conference's details.
    public static func followed(
        papers: [(paper: Paper, deadlines: PaperDeadlines)], starred: [DeadlineRow], now: Date
    ) -> [FollowedDeadline] {
        var owners: [String: [UUID]] = [:]
        var byID: [String: FollowedDeadline] = [:]
        var order: [String] = []
        for (paper, deadlines) in papers {
            for deadline in deadlines.upcoming(after: now) {
                guard let date = deadline.date else { continue }
                owners[deadline.id, default: []].append(paper.id)
                guard byID[deadline.id] == nil else { continue }
                let conference = deadlines.conference
                let title = deadline.kind == nil ? paper.title : conference?.fullTitle ?? paper.title
                byID[deadline.id] = FollowedDeadline(
                    deadline: deadline, date: date, name: conference?.seriesTitle ?? paper.title, title: title,
                    owner: paper.id.uuidString, paperID: paper.id, destination: .paper(paper.id),
                    start: paper.startedAt)
                order.append(deadline.id)
            }
        }
        for (id, ids) in owners where ids.count > 1 {
            guard var shared = byID[id],
                let source = papers.first(where: { $0.paper.id == ids[0] })?.deadlines.conference?.source
            else { continue }
            // Its round's, as a starred round's are, rather than one of its papers'.
            shared.owner = source.id
            shared.paperID = nil
            shared.destination = .deadline(source)
            shared.start = papers.filter { ids.contains($0.paper.id) }.map(\.paper.startedAt).min()
            byID[id] = shared
        }

        let covered = Set(papers.flatMap(\.deadlines.coveredIDs))
        for row in starred where row.state == .scheduled {
            for case let (kind, date?) in [(DeadlineKind.abstract, row.abstractDate), (.paper, row.paperDate)] {
                let id = row.id(of: kind)
                guard date > now, !covered.contains(id), byID[id] == nil else { continue }
                let deadline = PaperDeadline(
                    id: id, source: .conference(kind), value: DeadlineValue(raw: "", date: date), timeZone: row.timeZone
                )
                byID[id] = FollowedDeadline(
                    deadline: deadline, date: date, name: row.name,
                    title: row.fullTitle, owner: row.id,
                    destination: .deadline(row.source))
                order.append(id)
            }
        }
        return order.compactMap { byID[$0] }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// The next deadline of each of their owners, nearest first, at most `limit` of them, for the
    /// menu bar.
    public static func upcoming(_ followed: [FollowedDeadline], limit: Int) -> [FollowedDeadline] {
        var seen = Set<String>()
        return Array(followed.filter { seen.insert($0.owner).inserted }.prefix(limit))
    }

    /// Reads the day of `yyyy-MM-dd HH:mm:ss` as UTC, rolling over impossible days such as
    /// `2026-11-31`. Only used to drop stale unreadable rows; such a date is never shown.
    static func naiveDate(_ raw: String) -> Date? {
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.gregorian(in: .gmt).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
