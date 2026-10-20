import DrBarKit
import DrBarUI
import SwiftUI

/// Hands the timelines what the user's data says about them: the people of the recipient groups,
/// whom the bars put on the blocks they work on, and whether the axes show dates or the days
/// from today.
struct TimelineEnvironment: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var store = store
        content
            .environment(\.planPeople, store.userData.people)
            .environment(\.axisLabels, $store.userData.settings.axisLabels)
    }
}
