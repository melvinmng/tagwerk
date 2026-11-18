import SwiftUI
import TagwerkCore

/// What deadline rows can open (deadline card, week, month; plan deadline-marking DL2).
struct DeadlineActions {
    var openEvent: (CalendarEvent) -> Void
    var openTask: (TaskID) -> Void
    var showDay: (PlanDay) -> Void
    /// Opens the preparation of a deadline ("Termin zuordnen …", DV1).
    var prepare: (ImportantDeadline) -> Void
}

/// Tap opens the deadline (event sheet or task), holding offers "Öffnen / Zum Tag springen / Termin zuordnen … /
/// Markierung entfernen". Removing a mark with preparation links asks once.
struct DeadlineInteractions: ViewModifier {
    let deadline: ImportantDeadline
    let model: PlanningModel
    let actions: DeadlineActions
    @State private var confirmingUnmark: CalendarEvent?

    func body(content: Content) -> some View {
        Button(action: open) { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Öffnen", systemImage: "chevron.right", action: open)
                Button("Zum Tag springen", systemImage: "arrow.right") { actions.showDay(deadline.day) }
                Button("Termin zuordnen …", systemImage: "link") { actions.prepare(deadline) }
                if deadline.kind == .markedEvent {
                    Button("Markierung entfernen", systemImage: "flag.slash", role: .destructive, action: unmark)
                }
            }
            .unmarkConfirmation(event: $confirmingUnmark, model: model)
    }

    private func open() {
        if let id = deadline.eventID, let event = model.event(id: id) {
            actions.openEvent(event)
        } else if let task = deadline.taskID {
            actions.openTask(task)
        } else {
            actions.prepare(deadline)
        }
    }

    private func unmark() {
        guard let id = deadline.eventID, let event = model.event(id: id) else { return }
        if model.preparationLinkCount(forDeadlineEvent: event) > 0 {
            confirmingUnmark = event
        } else {
            Task { await model.unmarkDeadline(event) }
        }
    }
}

extension View {
    func deadlineInteractions(_ deadline: ImportantDeadline, model: PlanningModel, actions: DeadlineActions) -> some View {
        modifier(DeadlineInteractions(deadline: deadline, model: model, actions: actions))
    }

    /// "Markierung entfernen?" with the number of preparation links that are dissolved.
    func unmarkConfirmation(event: Binding<CalendarEvent?>, model: PlanningModel, onDone: @escaping () -> Void = {}) -> some View {
        confirmationDialog("Markierung entfernen?", isPresented: Binding(get: { event.wrappedValue != nil },
                                                                          set: { if !$0 { event.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: event.wrappedValue) { target in
            Button("Markierung entfernen", role: .destructive) {
                Task { await model.unmarkDeadline(target); onDone() }
            }
        } message: { target in
            Text("\(model.preparationLinkCount(forDeadlineEvent: target)) zugeordnete Termine werden gelöst. Im Kalender ändert sich nichts.")
        }
    }
}

/// One deadline as a row: flag, title with the mark "markiert", calendar or kind, preparation and distance.
struct DeadlineRowLabel: View {
    let deadline: ImportantDeadline
    let model: PlanningModel
    var showsDistance = true

    var body: some View {
        let text = DeadlineText(calendar: model.calendar)
        let calendarName = deadline.calendarID.flatMap(model.calendarTitle)
        let preparation = model.preparation[deadline.preparationKey]
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: deadline.kind == .epic ? "diamond.fill" : "flag.fill")
                .foregroundStyle(.red)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(deadline.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let badge = text.badge(deadline) { DeadlineBadge(text: badge) }
                }
                Text(text.detail(deadline, calendarName: calendarName)).font(.caption).foregroundStyle(.secondary)
                if let line = text.preparation(preparation) {
                    Label(line, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsDistance {
                Text(text.relative(deadline.day, today: model.today)).font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel(deadline, calendarName: calendarName, today: model.today,
                                                    preparation: preparation))
    }
}

/// The text mark "markiert" (text, not only colour).
struct DeadlineBadge: View {
    let text: String

    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(.red)
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.6), lineWidth: 1))
    }
}

/// A mark whose event is gone or moved: "übernehmen" for a candidate, "Termin zuordnen …" to pick another event,
/// "Entfernen" to drop the mark (never done silently).
struct OrphanedMarkRow: View {
    let orphan: OrphanedMark
    let model: PlanningModel
    @State private var reassigning = false

    var body: some View {
        let text = DeadlineText(calendar: model.calendar)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "flag.fill").foregroundStyle(.red).font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(orphan.title).font(.subheadline.weight(.semibold))
                        DeadlineBadge(text: String(localized: "markiert"))
                    }
                    Text(text.orphan(orphan, calendarName: model.calendarTitle(orphan.calendarID)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("prüfen").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if let candidate = orphan.candidate {
                    Button(text.adopt(candidate)) { Task { await model.adoptCandidate(orphan) } }
                } else {
                    Button("Termin zuordnen …") { reassigning = true }
                }
                Button("Entfernen", role: .destructive) { Task { await model.removeOrphanedMark(orphan) } }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .sheet(isPresented: $reassigning) { MarkReassignSheet(orphan: orphan, model: model) }
    }
}

/// Picks the event that carries a mark from now on (the old one is no longer in the calendar).
private struct MarkReassignSheet: View {
    let orphan: OrphanedMark
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(filtered) { event in
                Button {
                    Task { await model.reassignMark(orphan, to: event) }
                    dismiss()
                } label: { EventPickRow(event: event, model: model) }
                    .foregroundStyle(.primary)
            }
            .searchable(text: $search, prompt: "Termin suchen")
            .navigationTitle("Termin wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private var filtered: [CalendarEvent] {
        let events = model.reassignCandidates(for: orphan)
        guard !search.isEmpty else { return events }
        return events.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
}

/// The keyword card (DL3): an upcoming event whose title looks like an exam or a submission, detected locally.
struct DeadlineSuggestionCard: View {
    let model: PlanningModel
    @State private var askingSeries = false

    var body: some View {
        if let event = model.deadlineSuggestions.first {
            let text = DeadlineText(calendar: model.calendar)
            VStack(alignment: .leading, spacing: 8) {
                Label("Sieht nach einer Prüfung aus", systemImage: "flag")
                    .font(.caption.weight(.bold)).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.subheadline.weight(.semibold))
                    Text(text.moment(event.start, isAllDay: event.isAllDay)
                         + (model.calendarTitle(event.calendarID).map { " · " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Als Deadline markieren") {
                        if event.isRecurring { askingSeries = true } else { Task { await model.markDeadline(event, series: false) } }
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                    Button("Nein") { Task { await model.dismissDeadlineSuggestion(event) } }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .seriesMarkQuestion(isPresented: $askingSeries, event: event, model: model)
        }
    }
}

extension View {
    /// "Nur diesen Termin / Alle Termine der Serie" before marking a recurring event (decision 3).
    func seriesMarkQuestion(isPresented: Binding<Bool>, event: CalendarEvent?, model: PlanningModel) -> some View {
        confirmationDialog("Dieser Termin wiederholt sich", isPresented: isPresented, titleVisibility: .visible,
                           presenting: event) { event in
            Button("Nur diesen Termin") { Task { await model.markDeadline(event, series: false) } }
            Button("Alle Termine der Serie") { Task { await model.markDeadline(event, series: true) } }
        }
    }
}

/// A calendar event in a picker: title, series sign, time and calendar.
struct EventPickRow: View {
    let event: CalendarEvent
    let model: PlanningModel
    var isLinked = false

    var body: some View {
        let text = DeadlineText(calendar: model.calendar)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title + (event.isRecurring ? " ↻" : "")).lineLimit(2)
                Text(timeText(text) + (model.calendarTitle(event.calendarID).map { " · " + $0 } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isLinked { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
        .contentShape(Rectangle())
    }

    private func timeText(_ text: DeadlineText) -> String {
        guard !event.isAllDay else { return text.moment(event.start, isAllDay: true) }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = model.calendar.timeZone
        return text.moment(event.start, isAllDay: false) + " – " + event.end.formatted(style)
    }
}

// MARK: Preparation (DV1)

/// "Vorbereitung · 6 h 30 geplant": the linked events of a deadline, "Termin zuordnen …" and swipe to unlink.
struct PreparationSection: View {
    let deadline: ImportantDeadline
    let model: PlanningModel
    let onOpenEvent: (CalendarEvent) -> Void

    var body: some View {
        let events = model.preparationEvents(for: deadline)
        let summary = preparationSummary(events, now: model.now(), deadline: model.deadlineMoment(deadline))
        Section {
            ForEach(events) { event in
                Button { onOpenEvent(event) } label: {
                    EventPickRow(event: event, model: model)
                        .opacity(event.end <= model.now() ? 0.5 : 1)
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button("Lösen", role: .destructive) { Task { await model.unlinkPreparation(event, from: deadline) } }
                }
                .contextMenu {
                    Button("Zuordnung lösen", systemImage: "link.badge.minus", role: .destructive) {
                        Task { await model.unlinkPreparation(event, from: deadline) }
                    }
                }
            }
            NavigationLink("Termin zuordnen …") { EventLinkPicker(deadline: deadline, model: model) }
        } header: {
            Text(summary.count > 0 ? String(localized: "Vorbereitung · \(CapacityText.duration(summary.minutes)) geplant")
                                   : String(localized: "Vorbereitung"))
        } footer: {
            Text("Die Termine bleiben in ihren Kalendern und zählen wie bisher als belegte Zeit.")
        }
    }
}

/// The preparation of any deadline (P1 task, epic or event; decision 7) as its own sheet.
struct PreparationSheet: View {
    let deadline: ImportantDeadline
    let model: PlanningModel
    let onOpenEvent: (CalendarEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DeadlineRowLabel(deadline: deadline, model: model)
                }
                PreparationSection(deadline: deadline, model: model) { event in
                    dismiss()
                    onOpenEvent(event)
                }
            }
            .navigationTitle("Vorbereitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Events between now and the deadline to link as preparation, with search; a series asks
/// "Nur diesen Termin / Alle bis zur Deadline".
struct EventLinkPicker: View {
    let deadline: ImportantDeadline
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var askingSeries: CalendarEvent?

    var body: some View {
        let linked = Set(model.preparationEvents(for: deadline).map(\.id))
        List {
            Section(rangeTitle) {
                ForEach(filtered) { event in
                    Button { pick(event, linked: linked.contains(event.id)) } label: {
                        EventPickRow(event: event, model: model, isLinked: linked.contains(event.id))
                    }
                    .foregroundStyle(.primary)
                }
                if filtered.isEmpty { Text("Keine Termine bis zur Deadline").foregroundStyle(.secondary) }
            }
        }
        .searchable(text: $search, prompt: "Termin suchen")
        .navigationTitle("Termin wählen")
        .confirmationDialog(askingSeries.map { String(localized: "„\($0.title)“ wiederholt sich") } ?? "",
                            isPresented: Binding(get: { askingSeries != nil }, set: { if !$0 { askingSeries = nil } }),
                            titleVisibility: .visible, presenting: askingSeries) { event in
            Button("Nur diesen Termin") { link(event, series: false) }
            Button("Alle bis zur Deadline") { link(event, series: true) }
        }
    }

    private var rangeTitle: String {
        let text = DeadlineText(calendar: model.calendar)
        let from = text.moment(model.now(), isAllDay: true)
        let to = text.moment(deadline.day.startDate(in: model.calendar), isAllDay: true)
        return String(localized: "Bis zur Deadline · \(from) – \(to)")
    }

    private var filtered: [CalendarEvent] {
        let events = model.preparationCandidates(for: deadline)
        guard !search.isEmpty else { return events }
        return events.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func pick(_ event: CalendarEvent, linked: Bool) {
        if linked {
            Task { await model.unlinkPreparation(event, from: deadline) }
        } else if event.isRecurring {
            askingSeries = event
        } else {
            link(event, series: false)
        }
    }

    private func link(_ event: CalendarEvent, series: Bool) {
        Task {
            await model.linkPreparation(event, to: deadline, series: series)
            dismiss()
        }
    }
}

/// Deadlines after an event, to link the event as their preparation ("Zu Deadline zuordnen …").
struct DeadlinePicker: View {
    let event: CalendarEvent
    let model: PlanningModel
    let onDone: () -> Void
    @State private var askingSeries: ImportantDeadline?

    var body: some View {
        let deadlines = model.linkableDeadlines(for: event)
        List {
            ForEach(deadlines) { deadline in
                Button { pick(deadline) } label: { DeadlineRowLabel(deadline: deadline, model: model) }
                    .foregroundStyle(.primary)
            }
            if deadlines.isEmpty { Text("Keine Deadline nach diesem Termin").foregroundStyle(.secondary) }
        }
        .navigationTitle("Deadline wählen")
        .confirmationDialog(String(localized: "„\(event.title)“ wiederholt sich"),
                            isPresented: Binding(get: { askingSeries != nil }, set: { if !$0 { askingSeries = nil } }),
                            titleVisibility: .visible, presenting: askingSeries) { deadline in
            Button("Nur diesen Termin") { link(to: deadline, series: false) }
            Button("Alle bis zur Deadline") { link(to: deadline, series: true) }
        }
    }

    private func pick(_ deadline: ImportantDeadline) {
        if event.isRecurring { askingSeries = deadline } else { link(to: deadline, series: false) }
    }

    private func link(to deadline: ImportantDeadline, series: Bool) {
        Task {
            await model.linkPreparation(event, to: deadline, series: series)
            onDone()
        }
    }
}

/// "Zu Deadline zuordnen …" from a menu: the deadline picker as its own sheet.
struct DeadlinePickerSheet: View {
    let event: CalendarEvent
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DeadlinePicker(event: event, model: model) { dismiss() }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}

/// The menu of a calendar event in list mode and in the all-day row (DL2): "Öffnen", "Als Deadline markieren" or
/// "Markierung entfernen", "Zu Deadline zuordnen …", "Auf Frei setzen". Not in the hour grid, where holding moves.
struct EventDeadlineMenu: View {
    let event: CalendarEvent
    let model: PlanningModel
    let onOpen: () -> Void
    let onMarkSeries: () -> Void
    let onLinkToDeadline: () -> Void
    let onUnmarkWithLinks: () -> Void

    var body: some View {
        Button("Öffnen", systemImage: "chevron.right", action: onOpen)
        if !model.isInDeadlineCalendar(event) {
            if model.isMarkedDeadline(event) {
                Button("Markierung entfernen", systemImage: "flag.slash", role: .destructive) {
                    if model.preparationLinkCount(forDeadlineEvent: event) > 0 {
                        onUnmarkWithLinks()
                    } else {
                        Task { await model.unmarkDeadline(event) }
                    }
                }
            } else {
                Button("Als Deadline markieren", systemImage: "flag") {
                    if event.isRecurring { onMarkSeries() } else { Task { await model.markDeadline(event, series: false) } }
                }
            }
        }
        if !model.isDeadlineEvent(event) {
            Button("Zu Deadline zuordnen …", systemImage: "link", action: onLinkToDeadline)
        }
        if !event.isAllDay {
            Button(event.isBusy ? "Auf Frei setzen" : "Auf Belegt setzen", systemImage: event.isBusy ? "circle.dashed" : "circle.fill") {
                Task { await model.setFree([event], free: event.isBusy, series: false) }
            }
        }
    }
}
