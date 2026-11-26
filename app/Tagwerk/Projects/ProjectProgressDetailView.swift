import SwiftUI
import TagwerkCore

/// The page of one project in the project progress (#332). It loads its data from the reference alone, so it can be pushed from the
/// overview and from the global search with `TasksDestination.projectProgress`, whether or not the overview has been opened.
struct ProjectProgressDetailView: View {
    let reference: ProjectProgressReference

    @Environment(AppEnvironment.self) private var environment
    @State private var choice = ProjectPeriodChoice.fourWeeks
    @State private var customStart = Calendar.tagwerk.date(byAdding: .weekOfYear, value: -8, to: UITestMode.now()) ?? UITestMode.now()
    @State private var customEnd = UITestMode.now()
    @State private var shownEvents = Self.eventPageSize
    @State private var expandedGroups = Set<String>()

    /// Entries of the history added by each tap on "Weitere zeigen", and rows shown per group of open items at first.
    static let eventPageSize = 25
    static let groupLimit = 5

    private var store: ProjectProgressStore { environment.projectProgress }
    private var calendar: Calendar { environment.planning.calendar }
    private var now: Date { UITestMode.now() }

    private var period: ProjectPeriod {
        switch choice {
        case .fourWeeks: .fourWeeks
        case .threeMonths: .threeMonths
        case .oneYear: .oneYear
        case .custom: .custom(start: PlanDay(date: customStart, calendar: calendar), end: PlanDay(date: customEnd, calendar: calendar))
        }
    }

    var body: some View {
        let state = store.state(of: reference)
        List {
            if let load = state.load {
                content(load, state: state)
            } else if case .failed(let failure, _) = state {
                Section {
                    Text(ProjectProgressTexts.failureText(failure)).foregroundStyle(.orangeText)
                    retryButton
                }
            } else {
                Section { ProgressView("Wird geladen …") }
            }
        }
        .navigationTitle(reference.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load(reference, force: true) }
        .task { await store.load(reference) }
    }

    private var retryButton: some View {
        Button("Erneut laden") { Task { await store.load(reference, force: true) } }
            .accessibilityIdentifier(AccessibilityID.ProjectProgress.retry)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ load: ProjectFactsLoad, state: ProjectProgressStore.LoadState) -> some View {
        let range = ProjectProgress.range(of: period, now: now, calendar: calendar)
        let summary = ProjectProgress.summary(facts: load.facts, period: period, now: now, calendar: calendar)
        if case .failed(let failure, _) = state {
            Section {
                Text(ProjectProgressTexts.failureText(failure)).foregroundStyle(.orangeText)
                retryButton
            }
        }
        headerSection(summary, range: range)
        periodSection(range)
        if load.facts.isEmpty {
            Section { Text("In diesem Projekt gibt es noch nichts.").foregroundStyle(.secondaryText) }
        } else {
            chartSection(summary, range: range)
            openItemsSections(load.facts)
            historySection(load.facts, range: range)
        }
        footerSection(load)
    }

    private func headerSection(_ summary: ProjectSummary, range: ProjectRange) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(ProjectProgressTexts.sourceLabel(reference.kind), systemImage: ProjectProgressTexts.sourceSymbol(reference.kind))
                    .font(.subheadline).foregroundStyle(.secondaryText)
                HStack(alignment: .top, spacing: 12) {
                    figure(summary.periodCompleted, "Erledigt")
                    figure(summary.periodCreated, "Neu")
                    figure(summary.open, "Offen")
                }
                Label(ProjectProgressTexts.trendText(summary.trend), systemImage: ProjectProgressTexts.trendSymbol(summary.trend))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProjectProgressTexts.isResting(summary.trend) ? Color.orangeText : Color.primary)
                Text(ProjectProgressTexts.periodSentence(summary, periodName: choice.periodName(range: range, calendar: calendar)))
                    .font(.subheadline).foregroundStyle(.secondaryText)
                Text(ProjectProgressTexts.movementText(summary.lastMovement, now: now, calendar: calendar))
                    .font(.caption).foregroundStyle(.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.ProjectProgress.figures)
            if reference.kind == .gitHubRepository, let url = URL(string: "https://github.com/\(reference.id)") {
                Link(destination: url) { Label("Auf GitHub öffnen", systemImage: "arrow.up.forward.square") }
            }
        }
    }

    private func figure(_ value: Int, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func periodSection(_ range: ProjectRange) -> some View {
        Section {
            Picker("Zeitraum", selection: $choice) {
                ForEach(ProjectPeriodChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.ProjectProgress.periodPicker)
            .onChange(of: choice) { shownEvents = Self.eventPageSize }
            if choice == .custom {
                DatePicker("Von", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                DatePicker("Bis", selection: $customEnd, in: customStart...now, displayedComponents: .date)
            }
        }
    }

    private func chartSection(_ summary: ProjectSummary, range: ProjectRange) -> some View {
        Section {
            ProjectProgressChart(buckets: summary.buckets, calendar: calendar,
                                 summary: ProjectProgressTexts.chartSummary(summary.buckets, calendar: calendar))
            Text("Der offene Bestand ist aus den Anlage- und Schlussdaten zurückgerechnet.")
                .font(.footnote).foregroundStyle(.secondaryText)
        } header: {
            ProgressSectionHeader(title: "Verlauf je Woche")
        }
    }

    // MARK: Open items

    @ViewBuilder
    private func openItemsSections(_ facts: [ProjectItemFact]) -> some View {
        let today = PlanDay(date: now, calendar: calendar)
        let groups = ProjectProgress.openGroups(facts: facts, today: today, calendar: calendar)
        if !groups.isEmpty {
            group("blocked", "Blockiert", groups.blocked)
            group("blockers", "Blockiert andere", groups.blockers)
            group("overdue", "Überfällig", groups.overdue)
            group("soon", "Frist in den nächsten \(ProjectProgress.soonDays) Tagen", groups.soon)
            group("rest", "Weitere offene Punkte", groups.rest)
        }
    }

    @ViewBuilder
    private func group(_ id: String, _ title: LocalizedStringKey, _ items: [ProjectItemFact]) -> some View {
        if !items.isEmpty {
            let expanded = expandedGroups.contains(id)
            Section {
                ForEach(expanded ? items : Array(items.prefix(Self.groupLimit))) { itemRow($0) }
                if items.count > Self.groupLimit && !expanded {
                    Button("Alle zeigen (\(items.count))") { expandedGroups.insert(id) }
                }
            } header: {
                ProgressSectionHeader(title: title)
            }
            .accessibilityIdentifier(AccessibilityID.ProjectProgress.openItems)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ProjectItemFact) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.body)
            let detail = ProjectProgressTexts.itemDetail(item, now: now, calendar: calendar)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondaryText) }
        }
        if let url = item.url {
            Link(destination: url) { label }.foregroundStyle(.primary)
        } else {
            label
        }
    }

    // MARK: History

    @ViewBuilder
    private func historySection(_ facts: [ProjectItemFact], range: ProjectRange) -> some View {
        let events = ProjectProgress.events(facts: facts, in: range)
        Section {
            if events.isEmpty {
                Text("Im Zeitraum gab es keine erledigten oder neuen Einträge.").foregroundStyle(.secondaryText)
            }
            ForEach(Array(events.prefix(shownEvents))) { event in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProjectProgressTexts.eventText(event))
                        Text(event.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption).foregroundStyle(.secondaryText)
                    }
                } icon: {
                    Image(systemName: ProjectProgressTexts.eventSymbol(event.kind)).foregroundStyle(.secondaryText)
                }
            }
            if events.count > shownEvents {
                Button("Weitere zeigen") { shownEvents += Self.eventPageSize }
            }
        } header: {
            ProgressSectionHeader(title: "Verlauf")
        }
        .accessibilityIdentifier(AccessibilityID.ProjectProgress.history)
    }

    // MARK: Footer

    @ViewBuilder
    private func footerSection(_ load: ProjectFactsLoad) -> some View {
        Section {
            if load.isTruncated {
                Text("Es wurden nicht alle Einträge geladen; ältere Wochen können zu niedrig oder zu hoch ausfallen.")
            }
            if reference.kind == .remindersList {
                Text("Gelöschte Erinnerungen fehlen im Verlauf, wiederkehrende zählen als eine offene Aufgabe.")
            }
            if reference.kind == .local {
                Text("Aufgaben, die vor der Wochenauswertung erledigt wurden, haben kein Datum und fehlen in den Wochen.")
            }
            Text("Stand: \(load.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.footnote).foregroundStyle(.secondaryText)
        .listRowBackground(Color.clear)
    }
}
