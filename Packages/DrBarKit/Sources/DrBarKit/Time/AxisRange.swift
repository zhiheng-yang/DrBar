import Foundation

/// How far ahead of today a timeline reaches when it is not zoomed: a week, or 1, 3 or 6 months.
public enum AxisRange: String, CaseIterable, Codable, Sendable {
    case week, month, threeMonths, sixMonths

    /// How much the axis shows from the start of today.
    public var length: DateComponents {
        switch self {
        case .week: DateComponents(day: 7)
        case .month: DateComponents(month: 1)
        case .threeMonths: DateComponents(month: 3)
        case .sixMonths: DateComponents(month: 6)
        }
    }

    /// The days before today, where what has just passed is drawn faint: about a fourteenth of the
    /// range (2 days of a month, a week of 3 months, 2 weeks of 6), and yesterday for a week.
    var recentDays: Int {
        switch self {
        case .week: 1
        case .month: 2
        case .threeMonths: 7
        case .sixMonths: 14
        }
    }

    /// The range as earlier versions stored it, in months.
    init?(months: Int) {
        guard let range = Self.allCases.first(where: { $0.length == DateComponents(month: months) }) else {
            return nil
        }
        self = range
    }
}
