import SwiftUI
import TagwerkCore

/// The search sheet: a field, the kind marks and the sections of the hits (spec §6).
struct SearchSheet: View {
    @Bindable var model: SearchModel
    /// Shows a day in "Planen"; the sheet closes first.
    let onShowDay: (PlanDay) -> Void
    /// Shows a task in "Aufgaben"; the sheet closes first.
    let onShowTask: (TaskID) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    init(model: SearchModel, onShowDay: @escaping (PlanDay) -> Void, onShowTask: @escaping (TaskID) -> Void) {
        self.model = model
        self.onShowDay = onShowDay
        self.onShowTask = onShowTask
    }

    private var calendar: Calendar { environment.planning.calendar }
    private var now: Date { environment.taskList.now() }

    var body: some View {
        NavigationStack {
            List {
                if model.query == nil {
                    introduction
                } else {
                    if model.results.isEmpty, model.eventState != .loading { noResults }
                    if model.eventState == .loading, model.filter != .tasks {
                        Section { SearchLoadingRow() } header: { Text(SearchTexts.header(.upcomingEvents, count: nil)) }
                    }
                    ForEach(displayedKinds, id: \.self) { kind in
                        sectionView(kind)
                    }
                    footerRow
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Suchen", text: $model.text)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { fieldFocused = false }
                    if !model.text.isEmpty {
                        Button { model.text = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Eingabe löschen")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                Button("Abbrechen") { dismiss() }
            }
            filterMarks
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var filterMarks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases, id: \.self) { filter in
                    markButton(title: Self.title(of: filter), isSelected: model.filter == filter) { model.filter = filter }
                        .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
                }
                Spacer(minLength: 12)
                Toggle(isOn: $model.includeCompleted) { Text("✓ Erledigte") }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(model.includeCompleted ? .accentColor : .secondary)
            }
        }
    }

    private func markButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    static func title(of filter: SearchFilter) -> String {
        switch filter {
        case .all: String(localized: "Alle")
        case .events: String(localized: "Termine")
        case .tasks: String(localized: "Aufgaben")
        }
    }

    // MARK: States

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Durchsucht Termine, Aufgaben, Notizen und die Einkaufsliste.")
                Text(SearchTexts.footer(windowStart: model.windowStart, isExtended: false, calendar: calendar))
                    .font(.footnote).foregroundStyle(.secondary)
                if environment.gateway.calendarAccessState != .fullAccess {
                    Text("Kein Zugriff auf Kalender – Termine werden nicht durchsucht.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private var noResults: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keine Treffer für „\(model.query?.text ?? "")“.")
                if model.eventState == .noAccess {
                    Text("Kein Zugriff auf Kalender – Termine werden nicht durchsucht.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.filter != .events, !model.includeCompleted {
                    Button("Erledigte einbeziehen") { model.includeCompleted = true }
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private var footerRow: some View {
        Section {
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if model.eventState != .noAccess, model.filter != .tasks {
                    Text(SearchTexts.footer(windowStart: model.windowStart,
                                            isExtended: model.windowStart != SearchWindow.initial(now: now, calendar: calendar).start,
                                            calendar: calendar))
                }
            }
        }
    }

    // MARK: Sections

    /// Kinds with hits, plus "Vergangene Termine" when only the row "Ältere Termine durchsuchen" is left to show.
    private var displayedKinds: [SearchSectionKind] {
        SearchSectionKind.allCases.filter { kind in
            if model.results.sections.contains(where: { $0.kind == kind }) { return true }
            return kind == .pastEvents && showsOlderEventsRow
        }
    }

    private var showsOlderEventsRow: Bool {
        model.filter != .tasks && model.eventState == .loaded && model.canExtendWindow
    }

    @ViewBuilder private func sectionView(_ kind: SearchSectionKind) -> some View {
        let section = model.results.sections.first { $0.kind == kind }
        let rows = section.map { model.visibleRows(in: $0) } ?? []
        Section {
            ForEach(rows) { row in
                rowView(row)
            }
            if let section, model.hiddenCount(in: section) > 0 {
                Button { model.showMore(kind) } label: {
                    Text("Weitere \(min(SearchModel.pageSize, model.hiddenCount(in: section))) zeigen")
                }
            }
            if kind == .pastEvents, showsOlderEventsRow {
                Button { Task { await model.extendWindow() } } label: {
                    HStack {
                        Text(SearchTexts.olderEventsRow(before: model.windowStart, calendar: calendar))
                        if model.isExtendingWindow { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isExtendingWindow)
            }
        } header: {
            Text(SearchTexts.header(kind, count: section?.rows.count))
                .accessibilityLabel(SearchTexts.headerAccessibility(kind, count: section?.rows.count))
                .accessibilityAddTraits(.isHeader)
        } footer: {
            sectionFooter(kind)
        }
    }

    @ViewBuilder private func sectionFooter(_ kind: SearchSectionKind) -> some View {
        switch kind {
        case .openTasks:
            if case .offline(let since, _) = environment.taskList.sourceStates[.github] {
                Text("GitHub: Stand von \(DateText.time(since, calendar: calendar))")
            }
        case .completedTasks:
            Text("Geschlossene Issues findet nur die GitHub-Suche.")
        default:
            EmptyView()
        }
    }

    // MARK: Rows

    @ViewBuilder private func rowView(_ row: SearchRow) -> some View {
        switch row {
        case .event(let eventRow, let match):
            SearchEventRow(row: eventRow, match: match, calendarName: model.calendarName(of: eventRow.event),
                           isDeadline: environment.planning.deadlineEventIDs(among: [eventRow.event]).contains(eventRow.event.id),
                           isPast: EventSeriesGrouping.isPast(eventRow.event, now: now, calendar: calendar),
                           now: now, calendar: calendar)
        case .task(let item, let match):
            SearchTaskRow(item: item, match: match, now: now, calendar: calendar,
                          isReadOnly: environment.taskList.sourceStates[item.id.source]?.isOffline == true) {}
        case .completed(let group, let match):
            SearchCompletedRow(group: group, match: match, now: now, calendar: calendar)
        case .online, .note, .shopping:
            EmptyView()
        }
    }
}
