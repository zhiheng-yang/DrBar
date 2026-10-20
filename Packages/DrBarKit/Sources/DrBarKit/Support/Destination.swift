import Foundation

/// A place in the app. Notifications carry one, so that a click opens what they are about.
public enum Destination: Codable, Hashable, Sendable {
    /// The planner window, on the page it last showed, or the overview.
    case planner
    /// The planner window's conferences, ready to be searched.
    case conferences
    case paper(UUID)
    /// A deadline of the list of earlier builds, which notifications from then still carry; it is
    /// now its paper's or its item's.
    case customDeadline(UUID)
    /// A conference deadline, shown in the deadline window.
    case deadline(DeadlineRow.Source)
}
