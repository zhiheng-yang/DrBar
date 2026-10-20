import DrBarKit
import DrBarUI
import SwiftUI

/// A week, or 1, 3 or 6 months, for the planner's toolbar, which the planner's timelines glide to.
/// Zoomed to anything else, none is selected.
struct RangePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let choice = Binding<AxisRange?>(
            get: { store.plannerPosition.zoom == 1 ? store.axisRange : nil },
            set: { range in
                guard let range else { return }
                withAnimation(reduceMotion ? nil : .glide) {
                    store.axisRange = range
                    store.plannerPosition.zoom = 1
                }
            })
        Picker("Range", selection: choice) {
            ForEach(AxisRange.allCases, id: \.self) { choice in
                Text(verbatim: Self.shortLabel(choice))
                    .accessibilityLabel(Text(verbatim: Self.longLabel(choice)))
                    .tag(Optional(choice))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Time axis range")
    }

    static func shortLabel(_ range: AxisRange) -> String {
        guard let months = range.length.month else {
            return String(localized: "1W", comment: "Short label of the one-week time axis range")
        }
        return String(localized: "\(months)M", comment: "Short label of the time axis range in months, e.g. 3M")
    }

    static func longLabel(_ range: AxisRange) -> String {
        switch range.length.month {
        case nil: String(localized: "1 Week")
        case 1: String(localized: "1 Month")
        case let months?: String(localized: "\(months) Months")
        }
    }
}
