import SwiftUI
import TagwerkCore

/// Day view: the hour grid by default (design §13.15 S1), the row list as an alternative. Both open the same
/// sheet for events, blocks and the lunch break (U1).
struct DayView: View {
    @Bindable var model: PlanningModel
    @Environment(AppEnvironment.self) private var environment
    let onOpenTask: (TaskID) -> Void
    let onShowTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    let deadlineActions: DeadlineActions
    @State private var editingHours = false
    /// Event menu (list mode, all-day row): series question, deadline picker and removal with links (DL2).
    @State private var markingSeries: CalendarEvent?
    @State private var linkingToDeadline: CalendarEvent?
    @State private var unmarking: CalendarEvent?
    @State private var blockFor: TaskItem?
    @State private var sheetEntry: DayEntry?
    @State private var showsGrid = true

    var body: some View {
        Group {
            if let plan = model.days.first {
                if showsGrid {
                    DayGridScreen(model: model, plan: plan, onOpenTask: onOpenTask, onEditRecurring: onEditRecurring,
                                  menuActions: plannedActions, summary: { summary(plan) },
                                  timelineHeader: { timelineHeader }, onOpenEntry: { sheetEntry = $0 },
                                  onPlanTask: { blockFor = $0 })
                } else {
                    listContent(plan)
                }
            } else {
                // Keeps a view in place before the first load; otherwise the parent's `.task` would never run.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { showsGrid = model.showsHourGrid }
        .sheet(item: $sheetEntry) { entry in EntrySheet(entry: entry, model: model, onShowTask: onShowTask) }
        .sheet(item: $linkingToDeadline) { event in DeadlinePickerSheet(event: event, model: model) }
        .seriesMarkQuestion(isPresented: Binding(get: { markingSeries != nil }, set: { if !$0 { markingSeries = nil } }),
                            event: markingSeries, model: model)
        .unmarkConfirmation(event: $unmarking, model: model)
        .sheet(isPresented: $editingHours) {
            if let plan = model.days.first {
                DayOverrideSheet(day: plan.day, calendar: model.calendar, current: model.workHours(on: plan.day)) { value in
                    model.setDayOverride(value, on: plan.day)
                    Task { await model.reload() }
                }
            }
        }
        .sheet(item: $blockFor) { task in
            if let plan = model.days.first {
                BlockSheet(task: task, day: plan.day, hours: model.workHours(on: plan.day), now: model.now(),
                           minutes: model.suggestedBlockMinutes(for: task), calendar: model.calendar) { start, minutes in
                    Task { await model.createBlock(for: task, start: start, minutes: minutes) }
                }
            }
        }
    }

    // MARK: Shared parts

    /// Header, deadlines, capacity and all-day events (above the timeline in both modes).
    @ViewBuilder
    private func summary(_ plan: DayPlan) -> some View {
        PlanIntakeLine(model: model)
        // The one new element of phase 7: the morning card or today's focus, in the day view of today only.
        if model.scope == .day, model.anchor == model.today { RoutineCard(model: environment.routines, plan: plan) }
        DeadlineCard(model: model, actions: deadlineActions)
        DeadlineSuggestionCard(model: model)
        CapacityCard(model: model, plan: plan) { editingHours = true }
        if !model.allDayEvents(for: plan).isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Ganztägig").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(model.allDayEvents(for: plan)) { event in
                        Button { sheetEntry = .event(event, plan.links[event.id]) } label: {
                            Text(event.title).font(.subheadline).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { eventMenu(event, taskID: plan.links[event.id]) }
                    }
                }
            }
        }
    }

    private var timelineHeader: some View {
        HStack {
            Text("Ablauf").font(.headline)
            Spacer()
            Button {
                showsGrid.toggle()
                model.showsHourGrid = showsGrid
            } label: {
                Image(systemName: showsGrid ? "list.bullet" : "calendar.day.timeline.left")
            }
            .accessibilityLabel(showsGrid ? "Als Liste zeigen" : "Als Stundenraster zeigen")
        }
    }

    /// The shared menu plus the day-only entries that replaced the swipe actions.
    private func plannedActions(_ task: TaskItem) -> TaskMenuActions {
        var actions = menuActions(task)
        actions.createBlock = { blockFor = task }
        actions.shownDay = model.anchor
        // Focus belongs to today: the menu entry exists in the day view of today only, not for recurring occurrences.
        if model.scope == .day, model.anchor == model.today, !environment.routines.isRecurring(task) {
            actions.toggleFocus = { environment.routines.toggleFocus(task) }
            actions.isFocus = environment.routines.isFocus(task.id)
        }
        if model.planStore.assignment(for: task.id) != nil {
            actions.unassign = { Task { await model.unassign(task.id) } }
        }
        return actions
    }

    // MARK: List mode

    private func listContent(_ plan: DayPlan) -> some View {
        List {
            Section {
                summary(plan)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                let rows = model.timelineWithGaps(for: plan)
                if rows.isEmpty { Text("Keine Termine").foregroundStyle(.secondary) }
                ForEach(rows) { row in timelineRow(row, plan: plan) }
                // Open AI suggestions in list mode (mockup W3).
                ForEach(plan.suggestions.filter { $0.kind == .block }.sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }) { suggestion in
                    SuggestionRow(suggestion: suggestion)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } header: {
                timelineHeader.textCase(nil)
            }
            TaskSections(model: model, plan: plan, onOpenTask: onOpenTask, onEditRecurring: onEditRecurring,
                         menuActions: plannedActions)
        }
        .simultaneousGesture(pageSwipeGesture { model.step($0.step) })
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow, plan: DayPlan) -> some View {
        switch row {
        case .event(let event):
            let isDeadline = model.deadlineEventIDs.contains(event.id)
            Button { sheetEntry = .event(event, nil) } label: {
                TimelineLine(time: event.start, title: (isDeadline ? "⚑ " : "") + event.title, detail: eventDetail(event),
                             color: isDeadline ? .red : (event.isBusy ? .blue : .gray))
            }
            .foregroundStyle(.primary)
            .contextMenu { eventMenu(event, taskID: nil) }
        case .block(let event, let taskID):
            Button { sheetEntry = .event(event, taskID) } label: {
                TimelineLine(time: event.start,
                             title: (plan.day == model.today && model.focusTaskIDs.contains(taskID) ? "★ " : "") + event.title,
                             detail: CapacityText.duration(Int(event.end.timeIntervalSince(event.start) / 60)) + " · "
                                 + (model.canEditAsBlock(event) ? String(localized: "Zeitblock") : String(localized: "verknüpft")),
                             color: .green)
            }
            .foregroundStyle(.primary)
        case .lunch(let start, let minutes):
            Button { sheetEntry = .lunch(day: plan.day, range: start..<(start + minutes)) } label: {
                TimelineLine(time: plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(start * 60)),
                             title: String(localized: "Mittagspause"), detail: CapacityText.duration(minutes), color: .gray)
            }
            .foregroundStyle(.primary)
        case .gap(let range):
            GapLine(text: String(localized: "frei \(clock(range.lowerBound, on: plan.day))–\(clock(range.upperBound, on: plan.day))"))
                .dropDestination(for: String.self) { keys, _ in
                    guard let key = keys.first else { return false }
                    Task { await model.dropTask(key: key, atMinutes: range.lowerBound, on: plan.day) }
                    return true
                }
        }
    }

    /// The event menu of list mode and the all-day row (DL2).
    private func eventMenu(_ event: CalendarEvent, taskID: TaskID?) -> some View {
        EventDeadlineMenu(event: event, model: model, onOpen: { sheetEntry = .event(event, taskID) },
                          onMarkSeries: { markingSeries = event }, onLinkToDeadline: { linkingToDeadline = event },
                          onConfirmUnmark: { unmarking = event })
    }

    private func eventDetail(_ event: CalendarEvent) -> String {
        var parts = [String(localized: "bis \(event.end.formatted(date: .omitted, time: .shortened))")]
        if !event.isBusy { parts.append(String(localized: "Frei")) }
        if !event.mergedCalendarIDs.isEmpty { parts.append(String(localized: "\(event.mergedCalendarIDs.count + 1) Kalender")) }
        let text = DeadlineText(calendar: model.calendar)
        if model.deadlineEventIDs.contains(event.id) {
            parts.append(text.timelineMark(isMarked: !model.isInDeadlineCalendar(event)))
        }
        if let target = model.preparationTarget(forEventID: event.id) {
            parts.append(text.preparationMark(target, today: model.today))
        }
        return parts.joined(separator: " · ")
    }

    private func clock(_ minutes: Int, on day: PlanDay) -> String {
        day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Remaining time today (B1) or the day's capacity; opens the working hours of the day.
struct CapacityCard: View {
    @Environment(AppEnvironment.self) private var environment
    let model: PlanningModel
    let plan: DayPlan
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            details
            if !plan.isPast && !plan.capacity.isDayOff {
                Divider()
                AIPlanBar(scope: .day)
            }
            if plan.day == model.today, let entry = model.eveningEntry {
                Divider()
                eveningLine(entry)
            }
            if plan.day == model.today, environment.routines.eveningLine != nil {
                Divider()
                wrapUpLine
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "🛏 Tagesabschluss · Schlafzeit 23:00 · Checkliste 0 von 3 ›", independent of "Morgen planen"; after "Fertig"
    /// with a checkmark. Opens the sheet; nothing is written by looking at it.
    private var wrapUpLine: some View {
        let routines = environment.routines
        let isDone = routines.eveningLine?.isDone == true
        return Button {
            routines.openEvening()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "bed.double")
                    .foregroundStyle(isDone ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tagesabschluss").font(.subheadline.weight(.semibold))
                    Text(routines.captureEveningDetail(routines.eveningDay)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet den Tagesabschluss")
    }

    /// "☾ Morgen planen · Do. 19. Nov. · 3 h 15 frei · 2 von heute übrig" (MP2): a tap only shows that day;
    /// nothing is sent.
    private func eveningLine(_ entry: PlanningModel.EveningEntry) -> some View {
        Button {
            model.anchor = entry.day
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DayPanelText.eveningTitle(day: entry.day, today: model.today, calendar: model.calendar))
                        .font(.subheadline.weight(.semibold))
                    Text(DayPanelText.eveningDetail(day: entry.day, freeMinutes: entry.freeMinutes, leftCount: entry.leftCount,
                                                    calendar: model.calendar))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Suggested minutes of the day, counted apart until accepted (mockup V1).
    private var suggestedMinutes: Int { plan.suggestions.compactMap(\.minutes).reduce(0, +) }

    private var details: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(plan.isPast ? String(localized: "Vergangen") : CapacityText.remaining(plan.capacity)).font(.headline)
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }
                if plan.capacity.remainingMinutes != nil, let hours = model.workHours(on: plan.day) {
                    Text(remainingDetail(hours)).font(.caption).foregroundStyle(.secondary)
                }
                CapacityBar(capacity: plan.capacity)
                if plan.capacity.estimatedCount > 0 {
                    Text("\(plan.capacity.estimatedCount) Aufgabe(n) ohne Aufwand mit Standarddauer gerechnet")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if suggestedMinutes > 0 {
                    let suggested = CapacityText.duration(suggestedMinutes)
                    let freeAfter = CapacityText.duration(PlanningModel.freeAfterAccepting(
                        free: plan.capacity.remainingMinutes ?? plan.capacity.freeMinutes, suggestions: plan.suggestions,
                        counted: plan.planInput?.countedTaskMinutes ?? [:]))
                    Label(String(localized: "\(suggested) vorgeschlagen · nach dem Übernehmen \(freeAfter) frei"), systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Arbeitszeit an diesem Tag ändern")
    }

    /// "ab jetzt · 13:20 bis 18:00 · ganzer Tag …", or "Arbeitszeit vorbei" after the end of work.
    private func remainingDetail(_ hours: WorkHours) -> String {
        let nowMinutes = Int(model.now().timeIntervalSince(plan.day.startDate(in: model.calendar)) / 60)
        let summary = CapacityText.summary(plan.capacity)
        let end = clock(hours.endMinutes)
        if nowMinutes >= hours.endMinutes { return String(localized: "Arbeitszeit vorbei · ganzer Tag \(summary)") }
        if nowMinutes > hours.startMinutes {
            return String(localized: "ab jetzt · \(clock(nowMinutes)) bis \(end) · ganzer Tag \(summary)")
        }
        return String(localized: "ab \(clock(hours.startMinutes)) bis \(end) · ganzer Tag \(summary)")
    }

    private func clock(_ minutes: Int) -> String {
        plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Below the timeline: planned tasks (list mode), "Heute offen, nicht zugeordnet" and "Überfällig"
/// (design §13.15 D1, user feedback 2026-11-18). Recurring reminders appear in these sections with their effort.
struct TaskSections: View {
    let model: PlanningModel
    let plan: DayPlan
    var showsPlanned = true
    let onOpenTask: (TaskID) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions

    var body: some View {
        let today = model.today
        if showsPlanned {
            Section("Geplant ohne Uhrzeit") {
                if plan.assigned.isEmpty {
                    Text(DayPanelText.emptyPlannedHint(day: plan.day, today: today, calendar: model.calendar))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(plan.assigned) { task in taskRow(task, isPastDue: plan.isPastDue.contains(task.id)) }
            }
        }
        let leftovers = model.leftovers(on: plan.day)
        if !leftovers.isEmpty {
            Section {
                ForEach(leftovers) { task in commitRow(task, moves: true) }
            } header: {
                HStack {
                    Text("Von heute übrig")
                    Spacer()
                    Button(DayPanelText.moveAllTitle(day: plan.day, today: today, calendar: model.calendar)) {
                        let day = plan.day
                        Task { await model.moveTasks(leftovers.map(\.id), to: day) }
                    }
                    .textCase(nil)
                }
            }
        }
        if !plan.openToday.isEmpty {
            Section {
                ForEach(plan.openToday) { task in commitRow(task) }
            } header: {
                Text(DayPanelText.dueSectionTitle(day: plan.day, today: today, calendar: model.calendar))
            } footer: {
                Text(DayPanelText.commitFooter(day: plan.day, today: today, calendar: model.calendar))
            }
        }
        if model.showsOverdue(on: plan.day), !model.overdue.isEmpty {
            Section("Überfällig") {
                ForEach(model.overdue) { task in commitRow(task, overdue: true) }
            }
        }
    }

    private func taskRow(_ task: TaskItem, isPastDue: Bool) -> some View {
        PlannedTaskRow(task: task, isPastDue: isPastDue, isFocus: isFocus(task.id))
            .contentShape(Rectangle())
            .onTapGesture { onOpenTask(task.id) }
            .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
    }

    /// The star of a focus task; only in the plan of today.
    private func isFocus(_ id: TaskID) -> Bool { plan.day == model.today && model.focusTaskIDs.contains(id) }

    /// A task that is not yet committed to the shown day, with its effort for recurring reminders and the commit
    /// button ("Heute", "Morgen", "Einplanen"); leftovers from today move with their blocks (`moves`).
    private func commitRow(_ task: TaskItem, overdue: Bool = false, moves: Bool = false) -> some View {
        let recurring = model.recurringItem(for: task, on: plan.day)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((recurring != nil ? "↻ " : "") + (isFocus(task.id) ? "★ " : "") + task.title).lineLimit(2)
                HStack(spacing: 6) {
                    if let recurring, recurring.minutes > 0 {
                        Text("\(CapacityText.duration(recurring.minutes)) reserviert")
                    } else {
                        Text(EstimateHours.text(minutes: task.estimateMinutes))
                    }
                    if overdue, let due = task.due {
                        Text("fällig \(DueText.text(due, now: model.now(), calendar: model.calendar))").foregroundStyle(.red)
                    } else if overdue, let planned = model.planStore.assignment(for: task.id) {
                        Text("geplant \(planned.startDate(in: model.calendar).formatted(.dateTime.weekday(.abbreviated).day().month()))")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(DayPanelText.commitTitle(day: plan.day, today: model.today, calendar: model.calendar)) {
                let day = plan.day
                Task {
                    if moves { await model.moveTask(task.id, to: day) } else { await model.commitToShownDay(task.id) }
                }
            }
            .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenTask(task.id) }
        .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
    }
}

/// A free stretch in the timeline; tasks can be dropped on it (mockup C2).
private struct GapLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 48)
            RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3])).frame(width: 4)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "plus.circle").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 24)
        .accessibilityLabel(String(localized: "\(text), Aufgabe hier ablegen"))
    }
}

private struct TimelineLine: View {
    let time: Date
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A planned task without time (day and week views).
struct PlannedTaskRow: View {
    let task: TaskItem
    let isPastDue: Bool
    /// The task is today's focus: a star next to the title.
    var isFocus = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((isFocus ? "★ " : "") + task.title).lineLimit(2)
                HStack(spacing: 6) {
                    Text(EstimateHours.text(minutes: task.estimateMinutes))
                    if isPastDue { Label("nach Fälligkeit", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let priority = task.priority {
                Text(priority.label).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priority == .p1 ? Color.red.opacity(0.25) : Color.secondary.opacity(0.2), in: Capsule())
            }
        }
        .draggable(task.id.key)
    }
}
