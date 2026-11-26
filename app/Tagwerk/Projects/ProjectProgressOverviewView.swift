import SwiftUI
import TagwerkCore

/// All projects at a glance (#332): GitHub Projects and repositories, reminder lists and the local tasks, with a filter by source.
/// Opened from the row "Projektfortschritt" at the head of "Aufgaben".
struct ProjectProgressOverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter = ProjectSourceFilter.all

    private var store: ProjectProgressStore { environment.projectProgress }
    private var calendar: Calendar { environment.planning.calendar }
    private var now: Date { UITestMode.now() }

    /// One row of the overview: the project and what is known of it.
    private struct Row: Identifiable {
        var reference: ProjectProgressReference
        var state: ProjectProgressStore.LoadState
        var summary: ProjectSummary?
        var id: String { reference.key }
    }

    private var rows: [Row] {
        store.catalog.references.filter { filter.includes($0.kind) }.map { reference in
            let state = store.state(of: reference)
            let summary = state.load.map {
                ProjectProgress.summary(facts: $0.facts, period: .fourWeeks, now: now, calendar: calendar)
            }
            return Row(reference: reference, state: state, summary: summary)
        }
    }

    var body: some View {
        let rows = self.rows
        List {
            if store.isCatalogLoaded && store.catalog.references.isEmpty {
                emptyState
            } else {
                Section {
                    Picker("Quelle", selection: $filter) {
                        ForEach(ProjectSourceFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(AccessibilityID.ProjectProgress.sourceFilter)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if rows.contains(where: { $0.summary != nil }) { headerSection(rows) }
                rowSection(title: "Zuletzt bewegt", rows: sorted(rows.filter { isActive($0) }))
                rowSection(title: "Länger nicht bewegt", rows: sorted(rows.filter { isQuiet($0) }))
                rowSection(title: "Noch nicht geladen", rows: rows.filter { $0.summary == nil })
                if rows.isEmpty && store.isCatalogLoaded {
                    Text("Keine Projekte in dieser Quelle.").foregroundStyle(.secondaryText)
                }
                footer(rows)
            }
        }
        .navigationTitle("Projektfortschritt")
        .refreshable { await store.loadAll(force: true) }
        .task { await store.loadAll() }
    }

    // MARK: Sections

    private func isActive(_ row: Row) -> Bool {
        guard let trend = row.summary?.trend else { return false }
        switch trend {
        case .advancing, .growingBacklog, .steady: return true
        case .empty, .finished, .resting: return false
        }
    }

    private func isQuiet(_ row: Row) -> Bool { row.summary != nil && !isActive(row) }

    /// Newest movement first; projects without a known date last.
    private func sorted(_ rows: [Row]) -> [Row] {
        rows.sorted {
            switch ($0.summary?.lastMovement, $1.summary?.lastMovement) {
            case let (left?, right?) where left != right: left > right
            case (_?, nil): true
            case (nil, _?): false
            default: $0.reference.title.localizedStandardCompare($1.reference.title) == .orderedAscending
            }
        }
    }

    private func headerSection(_ rows: [Row]) -> some View {
        let loaded = rows.compactMap { row in row.state.load?.facts }
        let since = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let counts = ProjectProgress.counts(facts: loaded, since: since, until: now.addingTimeInterval(1))
        let resting = rows.filter { $0.summary.map { ProjectProgressTexts.isResting($0.trend) } ?? false }.count
        return Section {
            HStack(alignment: .top, spacing: 12) {
                figure(counts.completed, "Erledigt (7 Tage)")
                figure(counts.created, "Neu (7 Tage)")
                figure(resting, "Ruhend")
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func figure(_ value: Int, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowSection(title: LocalizedStringKey, rows: [Row]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    NavigationLink(value: TasksDestination.projectProgress(row.reference)) { rowLabel(row) }
                        .accessibilityIdentifier(AccessibilityID.ProjectProgress.row(row.reference.title))
                }
            }
        }
    }

    private func rowLabel(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.reference.title).font(.body.weight(.semibold))
            Label(ProjectProgressTexts.sourceLabel(row.reference.kind), systemImage: ProjectProgressTexts.sourceSymbol(row.reference.kind))
                .font(.caption).foregroundStyle(.secondaryText)
            if let summary = row.summary {
                Text(ProjectProgressTexts.countsText(summary)).font(.subheadline)
                ProgressView(value: summary.completedShare).accessibilityHidden(true)
                HStack {
                    Label(ProjectProgressTexts.trendText(summary.trend), systemImage: ProjectProgressTexts.trendSymbol(summary.trend))
                        .font(.subheadline)
                        .foregroundStyle(ProjectProgressTexts.isResting(summary.trend) ? Color.orangeText : Color.primary)
                    if !typeSize.isAccessibilitySize { Spacer() }
                }
                Text(ProjectProgressTexts.movementText(summary.lastMovement, now: now, calendar: calendar))
                    .font(.caption).foregroundStyle(.secondaryText)
                if case .failed(let failure, _) = row.state {
                    Text(ProjectProgressTexts.failureText(failure)).font(.caption).foregroundStyle(.orangeText)
                }
            } else {
                switch row.state {
                case .failed(let failure, _):
                    Text(ProjectProgressTexts.failureText(failure)).font(.subheadline).foregroundStyle(.orangeText)
                default:
                    ProgressView("Wird geladen …").font(.subheadline)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func footer(_ rows: [Row]) -> some View {
        let kinds = Set(rows.map(\.reference.kind))
        let truncated = rows.filter { $0.state.load?.isTruncated == true }.map(\.reference.title)
        Section {
            if filter.includes(.gitHubProject) && !store.catalog.gitHubConnected {
                note(ProjectProgressTexts.failureText(.notConnected))
            }
            if filter.includes(.remindersList) && !store.catalog.remindersAccess {
                note(ProjectProgressTexts.failureText(.noAccess))
            }
            if kinds.contains(.remindersList) {
                note(String(localized: "Gelöschte Erinnerungen fehlen im Verlauf, wiederkehrende zählen als eine offene Aufgabe."))
            }
            if kinds.contains(.gitHubProject) || kinds.contains(.gitHubRepository) {
                note(String(localized: "Bei GitHub zählen alle Issues des Projekts, nicht nur die dir zugewiesenen."))
            }
            ForEach(truncated, id: \.self) { title in
                note(String(localized: "Bei „\(title)“ wurden nicht alle Einträge geladen."))
            }
        }
        .listRowBackground(Color.clear)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondaryText)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch keine Projekte", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Verbinde GitHub oder erlaube Erinnerungen unter Einstellungen.")
        } actions: {
            Button("Einstellungen öffnen") { environment.requestedTab = 2 }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
