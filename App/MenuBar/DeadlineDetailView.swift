import DrBarKit
import DrBarUI
import SwiftUI

/// Everything about one round of a conference: exact times in both time zones, the comment,
/// the conference dates and place, the website, and the previous edition for reference.
struct DeadlineDetailView: View {
    /// `nil` when there is nothing to show, as in a deadline window that was never opened.
    let source: DeadlineRow.Source?
    /// Shows a back button (popover); `nil` in the deadline window.
    var onBack: (() -> Void)?

    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Back")
                .accessibilityLabel(Text("Back"))
            }
            if let source, let (series, edition) = store.catalog.edition(id: source.edition) {
                let round = edition.rounds.first { $0.id == source.round }
                ConferenceDetails(series: series, edition: edition, round: round)
            } else {
                ContentUnavailableView(
                    "Deadline Not Found", systemImage: "calendar",
                    description: Text("It may have passed or been removed from ccfddl."))
            }
        }
        .padding(.horizontal, PopoverView.margin)
        .padding(.vertical, 14)
    }
}

/// One edition as ccfddl describes it: its name and ranks, its bar with the whole cycle, every date
/// in both time zones, where and when it meets, the comment, the website and its papers on DBLP.
/// The menu bar window's details and the Conferences page show it.
struct ConferenceDetails: View {
    let series: ConferenceSeries
    let edition: ConferenceEdition
    let round: ConferenceRound?
    /// In a sheet, the undo manager of the window under it, as the sheet's own goes with it.
    var windowUndoManager: UndoManager?

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var ownUndoManager

    private var undoManager: UndoManager? {
        windowUndoManager ?? ownUndoManager
    }

    /// "AI · CCF A · CORE A* · TH-CPL A", the ranks that apply.
    private var ranks: String {
        let ranks = [
            series.displayRank.map(CCFCategory.rankName), series.displayCoreRank.map(CCFCategory.coreRankName),
            series.displayThcplRank.map(CCFCategory.thcplRankName),
        ]
        return ([series.category] + ranks.compactMap { $0 }).joined(separator: " · ")
    }

    /// "Nov 13, 2025" for ccfddl's `2025-11-13 23:59:59`.
    static func day(_ raw: String) -> String {
        Day(string: String(raw.prefix(10)))?.startDate().formatted(date: .abbreviated, time: .omitted) ?? raw
    }

    var body: some View {
        let zone = DeadlineTimeZone.ccf(edition.timeZone)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(series.title) \(String(edition.year))")
                            .font(.title3.weight(.semibold))
                    }
                    Text(series.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ranks)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StarButton(name: series.title, isStarred: store.isStarred(series.id)) {
                    store.toggleStar(series.id, undoManager: undoManager)
                }
            }

            if let round {
                // The same bar as in the list, with what follows the submission marked.
                DeadlineBar(
                    axis: store.axis, now: store.now,
                    state: round.closingDate != nil ? .scheduled : .notAnnounced,
                    paperDeadline: round.paper?.date, abstractDeadline: round.abstract?.date,
                    rebuttal: round.rebuttal?.date, decision: round.decision?.date, meeting: edition.meeting,
                    showsCycle: true
                )
                .barsGrowIn()
                .padding(.vertical, 4)
            }

            // The whole cycle in order: registration, submission, rebuttal, notification, the meeting.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Space.m, verticalSpacing: 8) {
                if let round {
                    ForEach(DeadlineKind.allCases, id: \.self) { kind in
                        if let value = round.value(kind) {
                            GridRow {
                                Text(kind.shortName)
                                    .foregroundStyle(.secondary)
                                DateLines(value: value, zone: zone, zoneLabel: edition.timeZone, now: store.now)
                            }
                        }
                    }
                }
                GridRow {
                    Text(SharedText.conference)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: edition.date?.announcedText ?? SharedText.notAnnounced)
                            .foregroundStyle(edition.date?.announcedText == nil ? .secondary : .primary)
                        if let place = edition.place?.announcedText {
                            Text(verbatim: MeetingText.place(place))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            .font(.callout)

            if !series.acceptance.isEmpty {
                AcceptanceHistory(rates: series.acceptance)
            }

            if let comment = round?.comment {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Last year's deadline beside the links, or under them where they leave no room.
            ViewThatFits(in: .horizontal) {
                HStack {
                    links
                    Spacer()
                    lastYear
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack { links }
                    lastYear
                }
            }
        }
    }

    @ViewBuilder
    private var links: some View {
        if let url = edition.url {
            Button("Open Website") { NSWorkspace.shared.open(url) }
        }
        if let url = series.dblpURL {
            Button("View on DBLP") { NSWorkspace.shared.open(url) }
        }
    }

    /// Shown, never used for bars, reminders or planning.
    @ViewBuilder
    private var lastYear: some View {
        if let previous = edition.lastYear {
            Text("Last year: \(Self.day(previous.paperDeadline))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help(Text("The paper deadline of \(series.title) \(String(previous.year))"))
        }
    }
}

/// One date in local time and in the conference's own time zone.
private struct DateLines: View {
    let value: DeadlineValue
    let zone: TimeZone?
    let zoneLabel: String
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let date = value.date, let zone {
                HStack(spacing: 6) {
                    Text(DeadlineText.localDateTime(date))
                        .foregroundStyle(date < now ? .secondary : .primary)
                    Text(date < now ? SharedText.passed : CountdownText.spoken(date.timeIntervalSince(now)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "\(DeadlineText.dateTime(date, in: zone)) (\(zoneLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !value.isAnnounced {
                Text(SharedText.notAnnounced)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "\(value.raw) (\(zoneLabel))")
                Text(zone == nil ? SharedText.unrecognizedTimeZone : SharedText.unreadable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .textSelection(.enabled)
    }
}

/// How many papers a conference took in its last years, the latest first: a bar each, as long as
/// its share of the papers submitted, beside the rate and the counts.
private struct AcceptanceHistory: View {
    let rates: [AcceptanceRate]

    /// How long a bar of the highest rate shown, or of half the papers, is drawn.
    private static let track: CGFloat = 90

    var body: some View {
        let shown = Array(rates.suffix(6).reversed())
        let scale = max(shown.map(\.rate).max() ?? 0, 0.5)
        VStack(alignment: .leading, spacing: 6) {
            Text("Acceptance Rate")
                .font(.callout)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.s, verticalSpacing: 5) {
                ForEach(shown, id: \.year) { rate in
                    GridRow {
                        Text(verbatim: String(rate.year))
                            .foregroundStyle(.secondary)
                        RoundedRectangle.bar(height: 8)
                            .fill(Palette.calm.opacity(rate.year == shown.first?.year ? 0.85 : 0.45))
                            .frame(width: max(Self.track * rate.rate / scale, 8), height: 8)
                            .frame(width: Self.track, alignment: .leading)
                        Text(verbatim: AcceptanceText.percent(rate.rate))
                            .gridColumnAlignment(.trailing)
                        Text(verbatim: AcceptanceText.counts(rate) ?? "")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The window a reminder or date-change notification opens.
struct DeadlineWindow: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        DeadlineDetailView(source: store.detailSource)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
    }
}
