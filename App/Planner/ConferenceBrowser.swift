import DrBarKit
import DrBarUI
import SwiftUI

/// Every conference to come, as ccfddl lists them: a row each with its name and full name, where
/// and when it meets, its ranks, field and acceptance rate, and its deadlines with the time left,
/// soonest first. Above them a search, All or Starred, past conferences and the order, then the
/// fields and ranks to keep to, each a button tinted while it is chosen; beside them, everything
/// about the selected one, which the toolbar hides and shows.
///
/// The keyboard works from the search field: ↓ and ↑ go through the list, and Return does what a
/// double click does: open the website, or, when choosing a paper's conference, choose.
struct ConferenceBrowser: View {
    /// The edition a paper aims at: always listed, and selected at first.
    var current: Paper.Target?
    /// In a sheet, the undo manager of the window under it, as the sheet's own goes with it.
    var windowUndoManager: UndoManager?
    /// Set when choosing a paper's conference: a double click, Return and Choose take an edition.
    var choose: ((TargetChoice) -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var ownUndoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var showsStarred = false
    @State private var selection: TargetChoice.ID?
    @AppStorage("conferencesIncludePast") private var includesPast = false
    @AppStorage("conferencesSort") private var sort = ConferenceSort.deadline
    @AppStorage("conferenceDetailsShown") private var showsDetails = true
    @FocusState private var isSearchFocused: Bool
    @State private var width: CGFloat = 0

    /// What the list needs beside the details, which it gives up below that.
    private static let listWidth: CGFloat = 440
    private static let detailsWidth: CGFloat = 320

    var body: some View {
        // What depends on the selection is drawn by views of its own, so that moving it does not
        // build the list again.
        let choices = choices
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                page(choices)
                // Always beside the list while choosing; on the page, while wanted and there is room.
                if choose != nil || (showsDetails && hasRoomForDetails) {
                    Divider()
                    SelectedConference(choices: choices, selection: $selection, windowUndoManager: windowUndoManager)
                        .frame(width: Self.detailsWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { width in
                self.width = width
            }
            if choose != nil {
                Divider()
                ChooserButtons(choices: choices, selection: $selection) { open($0, in: choices) }
            }
        }
        .toolbar {
            if choose == nil {
                ToolbarItem {
                    Button {
                        withAnimation(reduceMotion ? nil : .settle) { showsDetails.toggle() }
                    } label: {
                        Label("Details", systemImage: "sidebar.right")
                    }
                    .help(showsDetails && hasRoomForDetails ? Text("Hide Details") : Text("Show Details"))
                    .disabled(!hasRoomForDetails)
                }
            }
        }
        .background {
            Button("Find") { isSearchFocused = true }
                .keyboardShortcut("f")
                .hidden()
                .accessibilityHidden(true)
        }
        .onAppear {
            // The paper's edition, if the list still has it: old ones leave the catalog.
            let id = current.map(TargetChoice.id(of:))
            selection = choices.contains { $0.id == id } ? id : choices.first?.id
        }
        .task {
            if choose != nil || store.conferenceSearchRequested {
                focusSearch()
            }
        }
        .onChange(of: store.conferenceSearchRequested) { _, isRequested in
            if isRequested { focusSearch() }
        }
        .onChange(of: choices.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
    }

    private var undoManager: UndoManager? {
        windowUndoManager ?? ownUndoManager
    }

    private var hasRoomForDetails: Bool {
        width > Self.listWidth + Self.detailsWidth
    }

    /// No narrower than its rows need, which also keeps the window from growing tall to fit its
    /// filters in a narrow column.
    private func page(_ choices: [TargetChoice]) -> some View {
        VStack(spacing: 0) {
            filters(choices)
            Divider()
            ConferenceList(
                choices: choices, selection: $selection, toggleStar: toggleStar, open: { open($0, in: choices) }
            )
            .overlay { emptyState(choices) }
        }
        .frame(minWidth: Self.listWidth)
    }

    // MARK: Filters

    private func filters(_ choices: [TargetChoice]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SearchBar(spacing: Theme.Space.m) {
                searchField(choices)
                scope
            }
            // What is listed keeps to these while it is not starred or searched for.
            Group {
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(CCFCategory.all, id: \.self) { code in
                        chip(CCFCategory.name(code), value: code, in: \.categories)
                    }
                }
                FlowLayout(spacing: Theme.Space.l, lineSpacing: 5) {
                    ranks("CCF", CCFCategory.ranks, in: \.ccfRanks, name: CCFCategory.rankName)
                    ranks("CORE", CCFCategory.coreRanks, in: \.coreRanks, name: CCFCategory.coreRankName)
                    ranks("TH-CPL", CCFCategory.thcplRanks, in: \.thcplRanks, name: CCFCategory.thcplRankName)
                    if store.settings.filtersConferences {
                        Button("Show Everything") { showEverything() }
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                }
            }
            .disabled(showsStarred || isSearching)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private func searchField(_ choices: [TargetChoice]) -> some View {
        TextField("Search", text: $search, prompt: Text("Search conferences"))
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .onKeyPress(.downArrow) { move(by: 1, in: choices) }
            .onKeyPress(.upArrow) { move(by: -1, in: choices) }
            .onSubmit { open(selection, in: choices) }
            // In the chooser Esc cancels it, as its Cancel button does.
            .onExitCommand(perform: choose == nil ? { search = "" } : nil)
    }

    /// All or Starred, past conferences, and the order; what they change comes and goes in place.
    private var scope: some View {
        HStack(spacing: Theme.Space.m) {
            Picker("Conferences", selection: animated($showsStarred)) {
                Text("All").tag(false)
                Text("Starred").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Toggle("Show past conferences", isOn: animated($includesPast))
                .toggleStyle(.checkbox)
                .fixedSize()
            sortMenu
        }
    }

    private func animated<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in withAnimation(reduceMotion ? nil : .settle) { binding.wrappedValue = value } })
    }

    /// A list's ranks after its name, each by its letter, or "Not ranked" for those without one.
    private func ranks(
        _ title: String, _ options: [String], in list: FilterList, name: @escaping (String) -> String
    ) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(options, id: \.self) { rank in
                chip(rank == "N" ? name(rank) : rank, value: rank, in: list)
                    .accessibilityLabel(Text(verbatim: rank == "N" ? "\(title) \(name(rank))" : name(rank)))
            }
        }
    }

    /// Tinted while its option is kept to; with none tinted, everything is listed.
    private func chip(_ title: String, value: String, in list: FilterList) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.settings[keyPath: list].contains(value) },
                set: { isOn in
                    withAnimation(reduceMotion ? nil : .settle) {
                        if isOn {
                            store.userData.settings[keyPath: list].insert(value)
                        } else {
                            store.userData.settings[keyPath: list].remove(value)
                        }
                    }
                })
        )
        .toggleStyle(ChipStyle())
    }

    private func showEverything() {
        withAnimation(reduceMotion ? nil : .settle) { store.userData.settings.showEveryConference() }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: animated($sort)) {
                Text("Deadline").tag(ConferenceSort.deadline)
                Text("Name").tag(ConferenceSort.name)
                Text("CCF Rank").tag(ConferenceSort.rank)
                Text("Acceptance Rate").tag(ConferenceSort.acceptance)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort By")
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func focusSearch() {
        isSearchFocused = true
        store.conferenceSearchRequested = false
    }

    // MARK: List

    /// Stars or unstars a series; among the starred, its rows go or come back.
    private func toggleStar(_ series: String) {
        withAnimation(reduceMotion ? nil : .settle) { store.toggleStar(series, undoManager: undoManager) }
    }

    @ViewBuilder
    private func emptyState(_ choices: [TargetChoice]) -> some View {
        if !store.catalogLoaded {
            ProgressView()
        } else if choices.isEmpty {
            if isSearching {
                ContentUnavailableView.search(text: search)
            } else if showsStarred {
                ContentUnavailableView(
                    "No Starred Conferences", systemImage: "star",
                    description: Text("Star conferences to follow their deadlines."))
            } else {
                ContentUnavailableView {
                    Label("No Upcoming Deadlines", systemImage: "calendar")
                } description: {
                    Text("Try other categories or ranks.")
                } actions: {
                    Button("Show Everything") { showEverything() }
                }
            }
        }
    }

    // MARK: Choices

    private var choices: [TargetChoice] {
        let settings = store.settings
        let filter =
            showsStarred
            ? DeadlineFilter(scope: .following, search: search, includesPassed: includesPast)
            : DeadlineFilter(
                scope: .all, categories: settings.categories, ranks: settings.ccfRanks,
                coreRanks: settings.coreRanks, thcplRanks: settings.thcplRanks, search: search,
                includesPassed: includesPast)
        let built = TargetChoices.build(
            catalog: store.catalog, starred: store.userData.favoriteSeries, filter: filter, current: current,
            now: store.now)
        switch sort {
        case .deadline:
            return built
        case .name:
            return built.sorted { ($0.name.lowercased(), $0.target.year) < ($1.name.lowercased(), $1.target.year) }
        case .rank:
            return built.sorted { ($0.rankOrder, $0.deadlineOrder) < ($1.rankOrder, $1.deadlineOrder) }
        case .acceptance:
            return built.sorted { ($0.acceptanceOrder, $0.deadlineOrder) < ($1.acceptanceOrder, $1.deadlineOrder) }
        }
    }

    private func move(by offset: Int, in choices: [TargetChoice]) -> KeyPress.Result {
        guard !choices.isEmpty else { return .handled }
        let index = selection.flatMap { id in choices.firstIndex { $0.id == id } }
        selection = choices[index.map { min(max($0 + offset, 0), choices.count - 1) } ?? 0].id
        return .handled
    }

    /// Chooses the edition for the paper, or else opens its website.
    private func open(_ id: TargetChoice.ID?, in choices: [TargetChoice]) {
        guard let choice = choices.first(where: { $0.id == id }) else { return }
        if let choose {
            choose(choice)
        } else if let url = store.catalog.edition(series: choice.target.series, year: choice.target.year)?.1.url {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The conferences as rows, apart from the page so that moving the selection redraws only them.
private struct ConferenceList: View {
    let choices: [TargetChoice]
    @Binding var selection: TargetChoice.ID?
    let toggleStar: (String) -> Void
    /// What a double click does.
    let open: (TargetChoice.ID?) -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            List(choices, selection: $selection) { choice in
                let key = choice.target.series
                ConferenceRow(choice: choice, now: store.now, isStarred: store.isStarred(key)) {
                    toggleStar(key)
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: TargetChoice.ID.self) { ids in
                if let choice = choices.first(where: { $0.id == ids.first }) {
                    menu(for: choice)
                }
            } primaryAction: { ids in
                open(ids.first)
            }
            .onChange(of: selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private func menu(for choice: TargetChoice) -> some View {
        let key = choice.target.series
        Button(store.isStarred(key) ? "Unstar" : "Star") { toggleStar(key) }
        if let (series, edition) = store.catalog.edition(series: key, year: choice.target.year) {
            if let url = edition.url {
                Button("Open Website") { NSWorkspace.shared.open(url) }
            }
            if let url = series.dblpURL {
                Button("View on DBLP") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

/// Everything about the selected edition, for its round whose deadline comes next.
private struct SelectedConference: View {
    let choices: [TargetChoice]
    @Binding var selection: TargetChoice.ID?
    var windowUndoManager: UndoManager?

    @Environment(AppStore.self) private var store

    var body: some View {
        if let target = choices.first(where: { $0.id == selection })?.target,
            let (series, edition) = store.catalog.edition(series: target.series, year: target.year)
        {
            ScrollView {
                ConferenceDetails(
                    series: series, edition: edition, round: edition.round(id: nil, now: store.now),
                    windowUndoManager: windowUndoManager
                )
                .padding(Theme.Space.l)
            }
        } else {
            Color.clear
        }
    }
}

/// Cancel and Choose under the list, when choosing a paper's conference.
private struct ChooserButtons: View {
    let choices: [TargetChoice]
    @Binding var selection: TargetChoice.ID?
    let choose: (TargetChoice.ID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Choose") { choose(selection) }
                .keyboardShortcut(.defaultAction)
                .disabled(!choices.contains { $0.id == selection })
        }
        .padding(Theme.Space.m)
    }
}

/// The search field with the controls beside it, the field taking the rest of the line; on two
/// lines when that would leave the field narrower than `fieldWidth`.
private struct SearchBar: Layout {
    var fieldWidth: CGFloat = 160
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let controls = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width ?? fieldWidth + spacing + controls.width
        let field = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return isOneLine(width, controls)
            ? CGSize(width: width, height: max(field.height, controls.height))
            : CGSize(width: width, height: field.height + spacing + controls.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let controls = subviews[1].sizeThatFits(.unspecified)
        if isOneLine(bounds.width, controls) {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: bounds.width - spacing - controls.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        } else {
            let field = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + field.height + spacing), proposal: .unspecified)
        }
    }

    private func isOneLine(_ width: CGFloat, _ controls: CGSize) -> Bool {
        width - spacing - controls.width >= fieldWidth
    }
}

/// One of the lists of options the conferences are filtered by, in the settings.
private typealias FilterList = WritableKeyPath<AppSettings, Set<String>>

/// The order of the conference list: by the next deadline, as ccfddl has it, or by name, by CCF
/// rank, or by acceptance rate, the hardest first.
enum ConferenceSort: String {
    case deadline, name, rank, acceptance
}

/// A conference in the list, as ccfddl shows it: its name and full name, where and when it meets,
/// its ranks, field and acceptance rate on the left; the time left, large, and its deadlines in
/// local time on the right. It is given what it shows, as a list's rows do not see the store.
private struct ConferenceRow: View {
    let choice: TargetChoice
    let now: Date
    let isStarred: Bool
    let toggleStar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: choice.name)
                        .font(.headline)
                    Text(verbatim: String(choice.target.year))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let round = choice.roundLabel {
                        Text(verbatim: round)
                            .foregroundStyle(.secondary)
                    }
                    StarButton(name: choice.name, isStarred: isStarred, toggle: toggleStar)
                }
                Text(verbatim: choice.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(choice.detail)
                if let meeting = MeetingText.summary(
                    place: choice.place, flags: choice.flags, meeting: choice.meeting)
                {
                    Text(verbatim: meeting)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    tags
                }
                .padding(.top, 2)
                if let note = choice.note {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            deadlines
        }
        .padding(.vertical, 6)
        .opacity(choice.hasPassed ? 0.6 : 1)
    }

    @ViewBuilder
    private var tags: some View {
        if let rank = choice.rank {
            ConferenceTag(text: CCFCategory.rankName(rank))
        }
        if let rank = choice.coreRank {
            ConferenceTag(text: CCFCategory.coreRankName(rank))
        }
        if let rank = choice.thcplRank {
            ConferenceTag(text: CCFCategory.thcplRankName(rank))
        }
        ConferenceTag(text: CCFCategory.name(choice.category))
        if let acceptance = choice.acceptance {
            ConferenceTag(text: AcceptanceText.short(acceptance))
                .help(AcceptanceText.counts(acceptance) ?? "")
        }
    }

    /// The time left, then each deadline at its moment in local time; or why there is none.
    private var deadlines: some View {
        VStack(alignment: .trailing, spacing: 3) {
            switch choice.state {
            case .scheduled:
                if let date = choice.deadline {
                    let left = date.timeIntervalSince(now)
                    Group {
                        if left > 0 {
                            let urgency = Urgency(secondsLeft: left)
                            Text(CountdownText.amount(left))
                                .foregroundStyle(
                                    urgency == .critical || urgency == .near
                                        ? AnyShapeStyle(urgency.color) : AnyShapeStyle(.primary))
                        } else {
                            Text("Deadline passed")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    if let abstract = choice.abstractDeadline {
                        dateLine(DeadlineKind.abstract.shortName, abstract)
                    }
                    dateLine(DeadlineKind.paper.shortName, date)
                }
            case .notAnnounced:
                Text(SharedText.notAnnounced)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                if let lastYear = choice.lastYear {
                    Text("Last year: \(lastYear.startDate().formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            case .unreadable:
                Text(
                    DeadlineTimeZone.ccf(choice.timeZone) == nil
                        ? SharedText.unrecognizedTimeZone : SharedText.unreadable
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }
        }
        .fixedSize()
    }

    /// "Paper  Tue, Nov 17, 12:59"; on hover, the moment in the conference's own time zone too.
    private func dateLine(_ name: String, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: name)
                .foregroundStyle(.secondary)
            Text(verbatim: DeadlineText.localDateTime(date))
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(date <= now ? .tertiary : .primary)
        .help(
            [DeadlineText.localDateTime(date), DeadlineText.ownTime(date, choice.timeZone)].compactMap { $0 }
                .joined(separator: "\n"))
    }
}

/// An option of a filter: a small rounded button, tinted while it is chosen.
private struct ChipStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ChipLabel(isOn: configuration.isOn) { configuration.label }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}

private struct ChipLabel<Label: View>: View {
    let isOn: Bool
    @ViewBuilder let label: Label

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        label
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .background(isOn ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.fill.tertiary), in: shape)
            .overlay(shape.strokeBorder(isOn ? AnyShapeStyle(.tint.opacity(0.45)) : AnyShapeStyle(.clear)))
            .contentShape(shape)
    }
}

/// A rank, a field or a rate on a conference's row: small, in a light rounded box.
private struct ConferenceTag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// The star that follows a conference series, or stops following it. It is given what it shows,
/// so that it works in a list's rows, which do not see the store.
struct StarButton: View {
    let name: String
    let isStarred: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isStarred ? "star.fill" : "star")
                .foregroundStyle(isStarred ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(isStarred ? Text("Unstar") : Text("Star"))
        .accessibilityLabel(isStarred ? Text("Unstar \(name)") : Text("Star \(name)"))
    }
}

extension AppSettings {
    /// The lists the conference filters keep to, each with all its options.
    static var conferenceFilters: [(list: WritableKeyPath<AppSettings, Set<String>>, options: [String])] {
        [
            (\.categories, CCFCategory.all), (\.ccfRanks, CCFCategory.ranks), (\.coreRanks, CCFCategory.coreRanks),
            (\.thcplRanks, CCFCategory.thcplRanks),
        ]
    }

    /// Whether the filters leave something out: a list with some of its options chosen, not all.
    var filtersConferences: Bool {
        Self.conferenceFilters.contains { list, options in
            !self[keyPath: list].isEmpty && !Set(options).isSubset(of: self[keyPath: list])
        }
    }

    /// No option chosen in any list, which lists everything.
    mutating func showEveryConference() {
        for (list, _) in Self.conferenceFilters {
            self[keyPath: list] = []
        }
    }
}

#if DEBUG
#Preview("Conferences") {
    DemoPreview { ConferenceBrowser().frame(width: 900, height: 600) }
}
#endif
