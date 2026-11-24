import GitHubKit
import SwiftUI
import TagwerkCore
import UIKit

/// The search sheet: a field, the kind marks and the sections of the hits (spec §6).
struct SearchSheet: View {
    @Bindable var model: SearchModel
    /// Shows a day in "Planen"; the sheet closes first.
    let onShowDay: (PlanDay) -> Void
    /// Shows a task in "Aufgaben"; the sheet closes first.
    let onShowTask: (TaskID) -> Void
    /// Shows the folder list of a note in "Aufgaben" (`nil`: "Alle Notizen"); the sheet closes first.
    let onShowNoteFolder: (NotesScope) -> Void
    /// A hit for a day that only has gratitude: closes the search and shows the page of that day.
    let onShowMorningDay: (PlanDay) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var fieldFocused: Bool
    @State private var openTask: TaskItem?
    @State private var openContainers: [TaskContainer] = []
    @State private var openEvent: CalendarEvent?
    @State private var openNote: NoteTarget?
    @State private var showsShopping = false
    /// The task whose planned day is picked in a date sheet ("Anderer Tag …").
    @State private var planningDateFor: TaskItem?
    /// Short hint, e.g. "Der Termin wurde geändert."; shown as an alert together with errors of the task list.
    @State private var notice: String?

    init(model: SearchModel, onShowDay: @escaping (PlanDay) -> Void, onShowTask: @escaping (TaskID) -> Void,
         onShowNoteFolder: @escaping (NotesScope) -> Void = { _ in },
         onShowMorningDay: @escaping (PlanDay) -> Void = { _ in }) {
        self.model = model
        self.onShowDay = onShowDay
        self.onShowTask = onShowTask
        self.onShowNoteFolder = onShowNoteFolder
        self.onShowMorningDay = onShowMorningDay
    }

    private var calendar: Calendar { environment.planning.calendar }
    private var now: Date { environment.taskList.now() }

    /// A note to open in its own sheet (`UUID` is not `Identifiable`).
    private struct NoteTarget: Identifiable { let id: UUID }

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
            .safeAreaInset(edge: .bottom, spacing: 0) { undoBar }
            .animation(.spring(duration: 0.35), value: environment.taskList.lastCompleted?.id)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { fieldFocused = true }
        .sheet(item: $openTask, onDismiss: refreshAfterSheet) { task in
            AppTaskEditorSheet(item: task, containers: openContainers, allowsComments: true, respectsOffline: true,
                            onShowDay: onShowDay)
        }
        .sheet(item: $openEvent, onDismiss: refreshAfterSheet) { event in
            EventEntrySheet(event: event, onShowTask: onShowTask)
        }
        // Notes and the shopping list open as sheets with their own stack: the search hangs at the tab bar and
        // is reached from "Planen" as well, where the stack of "Aufgaben" shows nothing.
        .sheet(item: $openNote, onDismiss: refreshAfterSheet) { target in
            NoteEditorSheet(noteID: target.id)
        }
        .sheet(isPresented: $showsShopping, onDismiss: refreshAfterSheet) {
            ShoppingListSheet()
        }
        .sheet(item: $planningDateFor) { item in
            RescheduleDateSheet(item: item, calendar: calendar, now: now) { day in
                plan(item) { await environment.planning.assign(item.id, to: PlanDay(day)) }
            }
        }
        // A task with future time blocks asks before it moves; the dialog of "Planen" lies beneath this sheet.
        .confirmationDialog("Zeitblöcke mitverschieben?", isPresented: hasPendingBlockDecision, titleVisibility: .visible) {
            Button("Mitverschieben") { resolveBlocks(move: true) }
            Button("Blöcke löschen", role: .destructive) { resolveBlocks(move: false) }
            Button("Abbrechen", role: .cancel) { environment.planning.cancelBlockDecision() }
        } message: {
            Text("Für diese Aufgabe gibt es geplante Zeitblöcke im Kalender.")
        }
        .alert("Hinweis", isPresented: hasAlert) {
            Button("OK") { notice = nil; environment.taskList.clearError() }
        } message: {
            Text(notice ?? environment.taskList.lastError ?? "")
        }
    }

    private var hasAlert: Binding<Bool> {
        Binding(get: { notice != nil || environment.taskList.lastError != nil },
                set: { if !$0 { notice = nil; environment.taskList.clearError() } })
    }

    private var hasPendingBlockDecision: Binding<Bool> {
        Binding(get: { environment.planning.pendingBlockDecision != nil },
                set: { if !$0 { environment.planning.cancelBlockDecision() } })
    }

    /// After a sheet over the search closed, the hits may have changed (title, completion, date).
    private func refreshAfterSheet() {
        Task { await model.refresh() }
    }

    @ViewBuilder private var undoBar: some View {
        if let completed = environment.taskList.lastCompleted {
            UndoCapsule(title: completed.title, duration: 5,
                        onUndo: { Task { await environment.taskList.undoComplete(); await model.refresh() } },
                        onExpire: { if environment.taskList.lastCompleted?.id == completed.id { environment.taskList.dismissUndo() } })
                .id(completed.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Actions

    /// Tap on an event: opens the sheet for the event as "Planen" knows it; a changed event ends in a hint.
    private func open(_ event: CalendarEvent) {
        if let resolved = environment.planning.resolveEvent(matching: event) {
            openEvent = resolved
        } else {
            notice = String(localized: "Der Termin wurde geändert.")
            Task { await model.refresh() }
        }
    }

    private func open(_ task: TaskItem) {
        Task {
            openContainers = task.editableFields.contains(.container) ? await environment.taskList.containers(for: task.id.source) : []
            openTask = task
        }
    }

    /// Searches GitHub; an ended sign-in goes the way every other source takes (reload ends in the sign-in banner).
    private func searchOnline() async {
        await model.searchOnline()
        if model.onlineState == .failed(.signedOut) { await environment.taskList.reload(only: [.github]) }
    }

    /// "Im Plan zeigen" for a planned task, otherwise "In Aufgaben zeigen".
    private func showTask(_ item: TaskItem) {
        if let day = environment.planning.plannedInfo(for: item.id).day { onShowDay(day) } else { onShowTask(item.id) }
    }

    private func showInPlan(_ event: CalendarEvent) {
        onShowDay(PlanDay(date: event.start, calendar: calendar))
    }

    private func complete(_ task: TaskItem) {
        guard environment.taskList.sourceStates[task.id.source]?.isOffline != true else {
            notice = TaskListModel.message(for: TaskWriteError.offline)
            return
        }
        Task {
            await environment.taskList.complete(task.id)
            await model.refresh()
        }
    }

    /// Sets the planned day from a hit; the sheet stays open and VoiceOver says what happened.
    private func plan(_ item: TaskItem, _ assign: @escaping () async -> Void) {
        Task {
            await assign()
            // A task with future time blocks waits for the answer of the dialog; it announces afterwards.
            guard environment.planning.pendingBlockDecision == nil else { return }
            announcePlanned(item.id)
            await model.refresh()
        }
    }

    private func resolveBlocks(move: Bool) {
        let id = environment.planning.pendingBlockDecision?.taskID
        Task {
            await environment.planning.resolveBlocks(move: move)
            if let id { announcePlanned(id) }
            await model.refresh()
        }
    }

    private func announcePlanned(_ id: TaskID) {
        let planning = environment.planning
        guard let day = planning.plannedInfo(for: id).day else { return }
        AccessibilityNotification.Announcement(
            SearchTaskMenu.plannedAnnouncement(day: day, today: planning.today, calendar: calendar)).post()
    }

    /// "Fokus starten" from a VoiceOver action: closes the sheet, then asks for the start like the menu button does
    /// (start sheet, or an immediate start when "Dauer beim Start fragen" is off).
    private func startFocus(_ item: TaskItem) {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await environment.focus.requestStart(task: item, block: nil)
        }
    }

    /// "Im Ordner zeigen": the list of the note in "Aufgaben"; a note without a folder lies in "Notizen".
    private func showNoteFolder(_ note: NoteSearchItem) {
        // A day that only has gratitude lies in "Tagesstart".
        if note.routineDay != nil, let folder = environment.notes.folder(role: .morningRoutine) {
            onShowNoteFolder(.folder(folder.id))
            return
        }
        onShowNoteFolder(environment.notesScope(ofNote: note.id))
    }

    /// A note opens in its own sheet; a day that only has gratitude has no note, its page opens in "Aufgaben".
    private func open(_ note: NoteSearchItem) {
        if let day = note.routineDay { onShowMorningDay(day) } else { openNote = NoteTarget(id: note.id) }
    }

    private func reopen(_ task: TaskItem) {
        Task {
            await environment.taskList.reopen(task)
            await model.refresh()
        }
    }

    private func setDeadline(_ event: CalendarEvent, marked: Bool) {
        guard let resolved = environment.planning.resolveEvent(matching: event) else {
            notice = String(localized: "Der Termin wurde geändert.")
            return
        }
        Task {
            if marked { await environment.planning.unmarkDeadline(resolved) } else {
                await environment.planning.markDeadline(resolved, series: false)
            }
            await model.refresh()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondaryText).accessibilityHidden(true)
                    TextField("Suchen", text: $model.text)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { fieldFocused = false }
                    if !model.text.isEmpty {
                        Button { model.text = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondaryText)
                                .frame(minWidth: 44, minHeight: 44)
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
        .keepsKeyboardOnTap()
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
                    .font(.footnote).foregroundStyle(.secondaryText)
                if environment.gateway.calendarAccessState != .fullAccess {
                    Text("Kein Zugriff auf Kalender – Termine werden nicht durchsucht.")
                        .font(.footnote).foregroundStyle(.secondaryText)
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
                        .font(.footnote).foregroundStyle(.secondaryText)
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
            switch kind {
            case .pastEvents: return showsOlderEventsRow
            // The row "Auf GitHub suchen" lives in "Aufgaben", also without hits there.
            case .openTasks: return model.showsOnlineSearchRow || model.onlineState == .loading
            // A finished search without a hit still says so.
            case .online: return model.onlineState == .loaded
            default: return false
            }
        }
    }

    private var showsOlderEventsRow: Bool {
        model.filter != .tasks && model.eventState == .loaded && model.canExtendWindow
    }

    /// At least one note is hidden by the lock right now.
    private var hasConcealedNotes: Bool {
        let store = environment.notes
        let lock = environment.noteLock
        guard lock.protection.isActive, !lock.isUnlocked else { return false }
        let privateFolderIDs = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        return store.notes(.all).contains { lock.isConcealed($0, privateFolderIDs: privateFolderIDs) }
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
            // Hidden notes are found by their title only; the sheet says so under the note hits (NL4a).
            if kind == .notes, section != nil, hasConcealedNotes {
                Text("Gesperrte Notizen werden nur über den Titel gefunden.").font(.footnote).foregroundStyle(.secondaryText)
            }
            if kind == .online, model.onlineState == .loaded, section == nil {
                Text("Keine weiteren Treffer auf GitHub.").foregroundStyle(.secondaryText)
            }
            if kind == .openTasks {
                if model.onlineState == .loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("GitHub wird durchsucht …").foregroundStyle(.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                } else if model.showsOnlineSearchRow {
                    SearchOnlineAskRow(state: model.onlineState) { Task { await searchOnline() } }
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
        case .online:
            Text("Online-Treffer öffnen sich auf GitHub. Zum Bearbeiten in Tagwerk muss ein Issue dir zugewiesen sein und in einem Projekt liegen.")
        default:
            EmptyView()
        }
    }

    // MARK: Rows

    @ViewBuilder private func rowView(_ row: SearchRow) -> some View {
        switch row {
        case .event(let eventRow, let match):
            let event = eventRow.event
            SearchEventRow(row: eventRow, match: match, calendarName: model.calendarName(of: event),
                           isDeadline: environment.planning.deadlineEventIDs(among: [event]).contains(event.id),
                           isPast: EventSeriesGrouping.isPast(event, now: now, calendar: calendar),
                           now: now, calendar: calendar)
                .onTapGesture { open(event) }
                .contextMenu { eventMenu(event) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Öffnen")) { open(event) }
                .accessibilityAction(named: Text("Im Plan zeigen")) { showInPlan(event) }
        case .task(let item, let match):
            SearchTaskRow(item: item, match: match, now: now, calendar: calendar,
                          isReadOnly: environment.taskList.sourceStates[item.id.source]?.isOffline == true,
                          reminderMark: environment.taskList.reminderMarks[item.id.key]) { complete(item) }
                .onTapGesture { open(item) }
                .contextMenu { taskMenu(item) }
                .accessibilityAddTraits(.isButton)
                .modifier(SearchTaskAccessibilityActions(entries: taskMenuEntries(item),
                                                         isPlanned: environment.planning.plannedInfo(for: item.id).day != nil,
                                                         isFocusRunning: environment.focus.isRunning,
                                                         actions: taskMenuActions(item)))
        case .completed(let group, let match):
            let item = group.latest.item
            SearchCompletedRow(group: group, match: match, now: now, calendar: calendar)
                .onTapGesture { open(item) }
                .contextMenu {
                    Button("Öffnen", systemImage: "chevron.right") { open(item) }
                    Button("Wieder öffnen", systemImage: "arrow.uturn.backward") { reopen(item) }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Öffnen")) { open(item) }
                .accessibilityAction(named: Text("Wieder öffnen")) { reopen(item) }
        case .online(let issue):
            SearchOnlineRow(issue: issue, now: now, calendar: calendar)
                .onTapGesture { openURL(issue.url) }
                .contextMenu {
                    Button("Auf GitHub öffnen", systemImage: "arrow.up.right.square") { openURL(issue.url) }
                    Button("Link kopieren", systemImage: "link") { UIPasteboard.general.url = issue.url }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Auf GitHub öffnen")) { openURL(issue.url) }
                .accessibilityAction(named: Text("Link kopieren")) { UIPasteboard.general.url = issue.url }
        case .note(let note, let match):
            SearchNoteRow(note: note, match: match, calendar: calendar)
                .onTapGesture { open(note) }
                .contextMenu {
                    Button("Öffnen", systemImage: "chevron.right") { open(note) }
                    Button("Im Ordner zeigen", systemImage: "folder") { showNoteFolder(note) }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Öffnen")) { open(note) }
                .accessibilityAction(named: Text("Im Ordner zeigen")) { showNoteFolder(note) }
        case .shopping(let item, let match):
            SearchShoppingRow(item: item, match: match, onCheckOff: { Task { await model.checkOff(item) } })
                .onTapGesture { showsShopping = true }
                .contextMenu {
                    Button("Abhaken", systemImage: "checkmark.circle") { Task { await model.checkOff(item) } }
                    Button("Einkaufsliste öffnen", systemImage: "cart") { showsShopping = true }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Abhaken")) { Task { await model.checkOff(item) } }
                .accessibilityAction(named: Text("Einkaufsliste öffnen")) { showsShopping = true }
        }
    }

    @ViewBuilder private func eventMenu(_ event: CalendarEvent) -> some View {
        Button("Öffnen", systemImage: "chevron.right") { open(event) }
        Button("Im Plan zeigen", systemImage: "calendar") { showInPlan(event) }
        // The deadline entries need the event as "Planen" knows it.
        if let resolved = environment.planning.resolveEvent(matching: event), !environment.planning.isInDeadlineCalendar(resolved) {
            if environment.planning.isMarkedDeadline(resolved) {
                if !environment.planning.needsUnmarkConfirmation(resolved) {
                    Button("Markierung entfernen", systemImage: "flag.slash", role: .destructive) { setDeadline(event, marked: true) }
                }
            } else {
                Button("Als Deadline markieren", systemImage: "flag") { setDeadline(event, marked: false) }
            }
        }
    }

    private func taskMenuEntries(_ item: TaskItem) -> [SearchTaskMenu.Entry] {
        SearchTaskMenu.entries(for: item, isPlanned: environment.planning.plannedInfo(for: item.id).day != nil,
                               isOffline: environment.taskList.sourceStates[item.id.source]?.isOffline == true)
    }

    private func taskMenuActions(_ item: TaskItem) -> SearchTaskMenuActions {
        SearchTaskMenuActions(
            open: { open(item) },
            show: { showTask(item) },
            plan: { option in plan(item) { await environment.planning.plan(item.id, option: option) } },
            planOnDate: { planningDateFor = item },
            startFocus: { startFocus(item) },
            openOnGitHub: { if let url = item.url { openURL(url) } },
            complete: { complete(item) })
    }

    @ViewBuilder private func taskMenu(_ item: TaskItem) -> some View {
        SearchTaskMenuContent(item: item, entries: taskMenuEntries(item), actions: taskMenuActions(item))
    }
}
