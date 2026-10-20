import DrBarKit
import SwiftUI

/// A paper or an item without blocks, as the line of its group shows it.
public struct DueWork: Identifiable {
    public let id: UUID
    public let title: String
    public let overview: PaperOverview

    public init(id: UUID, title: String, overview: PaperOverview) {
        self.id = id
        self.title = title
        self.overview = overview
    }
}

/// The work of a group that has no blocks, on the line of the group's name, so that work that is
/// only due on a day takes no row of its own: a flag at each of its deadlines, named for its work,
/// the one each piece of work is marked by in red and the others gray. Flags on nearly the same
/// moment stand as one, named for all; a red one further away than the axis goes, or work with no
/// date yet, stands at the edge as an arrow. A click on a flag opens its work, its menu is the
/// work's, and its card tells what is due.
public struct DueLane<Actions: View>: View {
    public let work: [DueWork]
    public var axis: TimeAxis
    public let now: Date
    public var open: (UUID) -> Void
    public var card: (UUID) -> HoverCardSource?
    /// The menu of a piece of work, which VoiceOver offers as its actions too.
    public var menu: (UUID) -> Actions

    public init(
        work: [DueWork], axis: TimeAxis, now: Date, open: @escaping (UUID) -> Void,
        card: @escaping (UUID) -> HoverCardSource?, @ViewBuilder menu: @escaping (UUID) -> Actions
    ) {
        self.work = work
        self.axis = axis
        self.now = now
        self.open = open
        self.card = card
        self.menu = menu
    }

    public var body: some View {
        DeadlineTrack(
            axis: axis, now: now, deadlines: Self.deadlines(of: work, now: now), editing: nil, hovered: .constant(nil),
            height: Theme.laneHeight,
            lane: DeadlineTrack.Lane(
                titles: Dictionary(work.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
                open: open, menu: { AnyView(menu($0)) }, card: card)
        )
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            ForEach(work) { item in
                Text(PaperText.spoken(title: item.title, overview: item.overview, now: now))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { open(item.id) }
                    .accessibilityActions { menu(item.id) }
            }
        }
    }

    /// Every dated deadline of `work`, by its own name, which the line puts after its work's
    /// title. Work with none stands past the end.
    nonisolated static func deadlines(of work: [DueWork], now: Date) -> [TimelineDeadline] {
        work.flatMap { item -> [TimelineDeadline] in
            let dated = item.overview.deadlines.timeline(now: now, label: \.flagName).map { deadline in
                var deadline = deadline
                deadline.owner = item.id
                return deadline
            }
            guard dated.isEmpty else { return dated }
            let deadline =
                item.overview.deadlines.main
                ?? PaperDeadline(
                    id: "none", source: .own(item.id), value: DeadlineValue(raw: "", date: nil), timeZone: "")
            return [
                TimelineDeadline(
                    deadline: deadline, date: .distantFuture, style: .undated, label: item.title, owner: item.id)
            ]
        }
    }
}
