import AppKit
import DrBarKit
import DrBarUI
import SwiftUI

/// The image attached to a progress email, 560 pt wide on a light background, with labels in the
/// email's language: a banner with the time left, the paper, the stage it is in and how the plan
/// stands, then the plan, a row per kind of work, with today and the deadlines marked, and under it,
/// quiet, the other work the recipients may hear about.
///
/// The banner takes the color of the stage, and orange or red in the last week, and its number
/// counts down, so that no two updates look alike in the inbox and none reads as the last one again.
@MainActor
enum TimelineImage {
    static let width: CGFloat = 560
    /// The name column, which the bars of the plan and of the other work start after.
    static let labelWidth: CGFloat = 120

    struct Content {
        var title: String
        var blocks: [TimeBlock]
        var milestones: [Milestone]
        var deadlines: PaperDeadlines
        /// Whom the blocks name.
        var people: [UUID: Person]
        var status: PlanStatus
        var progress: Double
        /// The block under way, or else the next one.
        var stage: (block: TimeBlock, isNow: Bool)?
        var countdown: (days: Int, unit: String, caption: String)?
        var otherWork: [OtherWork]
        var language: MailLanguage
        var now: Date
    }

    /// Another paper or item, as the image shows it: its title, its blocks and its flag, nothing
    /// else.
    struct OtherWork: Identifiable {
        var id: UUID
        var title: String
        var blocks: [TimeBlock]
        var flag: [TimelineDeadline]
    }

    static func content(
        for paper: Paper, overview: PaperOverview, group: RecipientGroup, people: [UUID: Person],
        otherWork: [(paper: Paper, deadlines: PaperDeadlines)] = [], now: Date
    ) -> Content {
        let blocks = paper.blocksForUpdate(hidingBuffers: group.hidesBufferBlocks)
        let today = Day(now)
        let stage = PlanMath.currentBlock(blocks, today: today).map { ($0, $0.contains(today)) }
        // How the plan stands as the recipients see it, without the blocks kept from them.
        let status = PlanMath.status(blocks, milestones: paper.milestones, today: today, cutoffs: overview.cutoffs)
        return Content(
            title: paper.title, blocks: blocks, milestones: paper.milestones, deadlines: overview.deadlines,
            people: people, status: status, progress: PlanMath.progress(blocks), stage: stage,
            countdown: ProgressSummary.countdown(overview.deadlines, language: group.language, now: now),
            otherWork: otherWork.map { work in
                OtherWork(
                    id: work.paper.id, title: work.paper.title.trimmingCharacters(in: .whitespaces),
                    blocks: work.paper.blocksForUpdate(hidingBuffers: group.hidesBufferBlocks),
                    flag: work.deadlines.timeline(now: now).filter { $0.style == .flag })
            },
            language: group.language, now: now)
    }

    static func png(_ content: Content) -> Data? {
        let renderer = ImageRenderer(content: TimelineImageView(content: content))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The smallest range that shows the whole plan and the marked deadline, a week when they all
    /// fall within one; the other deadlines show as far as that reaches.
    static func range(for content: Content) -> AxisRange {
        let ends =
            content.blocks.map { $0.end.endDate() } + content.milestones.map { $0.date() }
            + [content.deadlines.flag?.date].compactMap { $0 }
        let last = ends.max() ?? content.now
        return AxisRange.allCases.first { TimeAxis(now: content.now, range: $0).end >= last } ?? .sixMonths
    }
}

struct TimelineImageView: View {
    let content: TimelineImage.Content

    var body: some View {
        let strings = MailStrings(content.language)
        let axis = TimeAxis(now: content.now, range: TimelineImage.range(for: content))
        // What else is on the axis, as far as it shows.
        let others = content.otherWork.filter { work in
            work.blocks.contains { $0.end.endDate() > axis.start && $0.start.startDate() < axis.end }
                || work.flag.contains { axis.contains($0.date) }
        }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            UpdateBanner(content: content, strings: strings)
            if content.blocks.isEmpty {
                Text(verbatim: strings.noBlocks)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                PaperTimeline(
                    blocks: content.blocks, milestones: content.milestones, deadlines: deadlines(strings),
                    axis: axis, now: content.now, labelWidth: TimelineImage.labelWidth, blockName: strings.blockName,
                    todayLabel: strings.today, milestonesLabel: strings.milestones, deadlinesLabel: strings.deadlines,
                    locale: content.language.locale, showsHelp: false)
            }
            if !others.isEmpty {
                OtherWorkRows(
                    title: strings.alsoWorkingOn, work: others, axis: axis, now: content.now,
                    showsAxis: content.blocks.isEmpty, todayLabel: strings.today, locale: content.language.locale)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: TimelineImage.width, alignment: .leading)
        .background(Color.white)
        // The image goes to someone else: the sender's accent color is not part of it.
        .tint(.blue)
        .environment(\.planPeople, content.people)
        // Dates, as the recipients read them on another day.
        .environment(\.axisLabels, .constant(.dates))
        .environment(\.colorScheme, .light)
        .environment(\.locale, content.language.locale)
    }

    /// Named in the email's language; the marked one with its venue, as the recipients see no
    /// header.
    private func deadlines(_ strings: MailStrings) -> [TimelineDeadline] {
        let deadlines = content.deadlines
        return deadlines.timeline(now: content.now) { deadline in
            strings.label(of: deadline, conference: deadline.id == deadlines.flag?.id ? deadlines.conference : nil)
        }
    }
}

/// What else the user is working on that the recipients may hear about, quiet under the plan, as
/// the conferences are under the papers in the menu bar window: a title and a thin bar each, with
/// its flag, on the plan's axis, whose dates it shows when there is no plan above.
private struct OtherWorkRows: View {
    let title: String
    let work: [TimelineImage.OtherWork]
    let axis: TimeAxis
    let now: Date
    let showsAxis: Bool
    let todayLabel: String
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if showsAxis {
                AxisHeader(axis: axis, now: now, todayLabel: todayLabel, locale: locale)
                    .padding(.leading, TimelineImage.labelWidth + Theme.Space.s)
            }
            ForEach(work) { work in
                HStack(spacing: Theme.Space.s) {
                    Text(verbatim: work.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: TimelineImage.labelWidth, alignment: .leading)
                    PlanBar(
                        axis: axis, now: now, blocks: work.blocks, deadlines: work.flag, height: Theme.quietBarHeight
                    )
                    .frame(maxHeight: .infinity)
                    .background(AxisGrid(axis: axis, now: now))
                }
                .frame(height: Theme.quietRowHeight)
            }
        }
    }
}

/// The top of the email's image: the days left in large type, then the paper, the stage it is in
/// and a chip with how the plan stands.
private struct UpdateBanner: View {
    let content: TimelineImage.Content
    let strings: MailStrings

    var body: some View {
        let accent = accent
        HStack(alignment: .center, spacing: Theme.Space.l) {
            if let countdown = content.countdown {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: "\(countdown.days)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(verbatim: countdown.unit)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                    Text(verbatim: countdown.caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 132, alignment: .leading)
                Rectangle()
                    .fill(accent.opacity(0.3))
                    .frame(width: 1, height: 50)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: content.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                if let stage = content.stage {
                    Text(verbatim: strings.stageLine(stage.block, isNow: stage.isNow, people: content.people))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: Theme.Space.s) {
                    Text(verbatim: strings.status(content.status))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(statusColor.opacity(0.14)))
                    if content.status != .noPlan {
                        Text(verbatim: strings.progress(content.progress))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent.opacity(0.22)))
    }

    /// Orange in the last week and red in the last three days; otherwise the color of the stage.
    private var accent: Color {
        if let days = content.countdown?.days, days <= 7 {
            return days <= 3 ? .red : .orange
        }
        return content.stage.map { BlockColor.color(for: $0.block) } ?? .blue
    }

    private var statusColor: Color {
        switch content.status {
        case .behind: .orange
        case .conflict: .red
        case .onTrack, .noPlan: .blue
        }
    }
}
