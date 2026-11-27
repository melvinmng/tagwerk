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
    /// The time of the page, read on the device for the period it was read for (see `TimeLoad`).
    @State private var time: (load: TimeLoad, summary: ProjectTimeSummary)?
    /// The evaluation of the activity log for the same period, read together with the time (the log only grows, so it is not read while
    /// the page is drawn).
    @State private var statusHistory: (load: TimeLoad, value: ProjectStatusHistory)?
    /// The "Neue Aufgabe" sheet opened with "+" for this project (#348).
    @State private var creating: NewTaskDestination?

    /// Entries of the history added by each tap on "Weitere zeigen", and rows shown per group of open items at first.
    static let eventPageSize = 25
    static let groupLimit = 5

    /// What the time section depends on: the period and the facts it was calculated from. A change reads the records again.
    private struct TimeLoad: Hashable {
        var choice: ProjectPeriodChoice
        var customStart: Date
        var customEnd: Date
        var factsFetchedAt: Date?
    }

    private var store: ProjectProgressStore { environment.projectProgress }
    private var timeLoad: TimeLoad {
        TimeLoad(choice: choice, customStart: choice == .custom ? customStart : .distantPast,
                 customEnd: choice == .custom ? customEnd : .distantPast, factsFetchedAt: store.facts(of: reference)?.fetchedAt)
    }
    private var calendar: Calendar { environment.planning.calendar }
    private var now: Date { UITestMode.now() }
    /// Every kind of project has a source to create a task in: issues for a GitHub repository or Project, tasks for a reminder list and
    /// the local tasks. The "+" is there while that source can take one (GitHub connected, access to Reminders).
    private var destination: NewTaskDestination { NewTaskDestination(reference: reference) }

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
        .task(id: timeLoad) { readTime() }
        .toolbar {
            if destination.isAvailable(in: environment.taskList) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = destination } label: { Label(destination.actionName, systemImage: "plus") }
                        .accessibilityIdentifier(AccessibilityID.ProjectProgress.newTask)
                }
            }
        }
        // The figures of the page follow the new item once it is created.
        .sheet(item: $creating) { destination in
            NewTaskSheet(model: environment.taskList, onCreated: { Task { await store.load(reference, force: true) } },
                         destination: destination)
        }
    }

    /// Reads the recorded time for the tasks of the project and the period. Local data only, so it needs no waiting state.
    private func readTime() {
        guard let facts = store.facts(of: reference) else { return }
        let range = ProjectProgress.range(of: period, now: now, calendar: calendar)
        let keys = ProjectFactsMapping.timeKeys(of: reference.kind, facts: facts.facts)
        let inputs = store.timeInputs(taskKeys: keys, range: range)
        let loadKey = timeLoad
        time = (loadKey, ProjectTime.summary(inputs: inputs, taskKeys: keys, range: range, calendar: calendar))
        statusHistory = (loadKey, store.statusHistory(of: reference, facts: facts.facts, range: range))
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
            timeSection(load.facts)
            statusHistorySections()
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

    // MARK: Time

    @ViewBuilder
    private func timeSection(_ facts: [ProjectItemFact]) -> some View {
        let estimate = ProjectTime.openEstimate(facts: facts)
        Section {
            if let time, time.load == timeLoad {
                let summary = time.summary
                if summary.hasData {
                    ProjectTimeChart(weeks: summary.weeks, calendar: calendar,
                                     summary: ProjectProgressTexts.timeChartSummary(summary.weeks, calendar: calendar))
                } else {
                    // Nothing recorded is not a measured zero: no "0 h", and the reason when the blocks cannot be read.
                    Text("Keine Zeitdaten im Zeitraum").foregroundStyle(.secondaryText)
                        .accessibilityIdentifier(AccessibilityID.ProjectProgress.timeEmpty)
                }
                timeRow("planned", "Eingeplant", ProjectProgressTexts.plannedText(summary))
                timeRow("invested", "Investiert", ProjectProgressTexts.investedText(summary))
                timeRow("estimate", "Offene Schätzungen", ProjectProgressTexts.estimateText(estimate))
            } else {
                ProgressView()
            }
        } header: {
            ProgressSectionHeader(title: "Zeit")
        }
        // The explanation in a section of its own like the footer of the page, which the audits pass.
        Section {
            Text("Eingeplant: Zeitblöcke, die Tagwerk für diese Aufgaben angelegt hat.")
            Text("Investiert: Fokus-Timer und Blöcke bis zum Erledigen in Tagwerk.")
            Text("Aufgaben, die nicht in Tagwerk bearbeitet wurden, haben keine Zeit.")
        }
        .font(.footnote).foregroundStyle(.secondaryText)
        .listRowBackground(Color.clear)
    }

    /// One line of the time section; a single element, title as label and the time as value.
    private func timeRow(_ name: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        valueRow(id: AccessibilityID.ProjectProgress.timeRow(name), Text(title), value)
    }

    /// A line with a title and a value, one element for VoiceOver. The value is in the primary colour: the secondary grey on the grouped
    /// background is reported by the contrast audit.
    private func valueRow(id: String, _ title: Text, _ value: String) -> some View {
        LabeledContent { Text(value).foregroundStyle(.primary) } label: { title }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityIdentifier(id)
    }

    // MARK: Status history

    /// What the user changed through Tagwerk in the period: moves between Status values and the time spent in them (GitHub Projects),
    /// reopenings and reschedules. The log is local and young, so the note under it says what it covers.
    @ViewBuilder
    private func statusHistorySections() -> some View {
        Section {
            if let cached = statusHistory, cached.load == timeLoad {
                statusHistoryRows(cached.value)
            } else {
                ProgressView()
            }
        } header: {
            ProgressSectionHeader(title: "Änderungen in Tagwerk")
        }
        if let statusHistory {
            Section {
                Text(ProjectProgressTexts.statusHistoryNote(since: statusHistory.value.loggedSince))
                    .accessibilityIdentifier(AccessibilityID.ProjectProgress.statusNote)
            }
            .font(.footnote).foregroundStyle(.secondaryText)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func statusHistoryRows(_ history: ProjectStatusHistory) -> some View {
        Group {
            if history.isEmpty {
                Text("Im Zeitraum wurde keine Änderung aus Tagwerk protokolliert.").foregroundStyle(.secondaryText)
                    .accessibilityIdentifier(AccessibilityID.ProjectProgress.statusEmpty)
            } else {
                if history.statusChanges > 0 { valueRow(id: AccessibilityID.ProjectProgress.statusRow("changes"), Text("Statuswechsel"), "\(history.statusChanges)") }
                ForEach(history.transitions.prefix(Self.groupLimit)) { transition in
                    valueRow(id: AccessibilityID.ProjectProgress.statusRow("transition.\(transition.from)>\(transition.to)"),
                             Text(verbatim: ProjectProgressTexts.transitionText(transition)), "\(transition.count)×")
                }
                ForEach(history.durations.prefix(Self.groupLimit)) { duration in
                    valueRow(id: AccessibilityID.ProjectProgress.statusRow("duration.\(duration.status)"), Text(verbatim: duration.status),
                             ProjectProgressTexts.statusDurationText(duration.seconds))
                }
                if history.reopenCount > 0 { valueRow(id: AccessibilityID.ProjectProgress.statusRow("reopened"), Text("Wieder geöffnet"), "\(history.reopenCount)") }
                if history.dueDateChanges > 0 { valueRow(id: AccessibilityID.ProjectProgress.statusRow("dueDates"), Text("Frist verschoben"), "\(history.dueDateChanges)") }
                if history.planDayChanges > 0 { valueRow(id: AccessibilityID.ProjectProgress.statusRow("planDays"), Text("Arbeitstag verschoben"), "\(history.planDayChanges)") }
            }
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
