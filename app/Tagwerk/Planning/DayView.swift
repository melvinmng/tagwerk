import SwiftUI
import TagwerkCore

/// Day view: the hour grid by default (design §13.15 S1), the row list as an alternative. Both open the same
/// sheet for events, blocks and the lunch break (U1).
struct DayView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let onShowTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    @State private var editingHours = false
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
        DayHeader(model: model) { model.scope = .month }
        DeadlineCard(deadlines: model.upcomingDeadlines, today: model.today, calendar: model.calendar)
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
            } header: {
                timelineHeader.textCase(nil)
            }
            TaskSections(model: model, plan: plan, onOpenTask: onOpenTask, onEditRecurring: onEditRecurring,
                         menuActions: plannedActions)
        }
        .simultaneousGesture(daySwipe)
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow, plan: DayPlan) -> some View {
        switch row {
        case .event(let event):
            Button { sheetEntry = .event(event, nil) } label: {
                TimelineLine(time: event.start, title: event.title,
                             detail: "bis \(event.end.formatted(date: .omitted, time: .shortened))"
                                 + (event.isBusy ? "" : " · Frei")
                                 + (event.mergedCalendarIDs.isEmpty ? "" : " · \(event.mergedCalendarIDs.count + 1) Kalender"),
                             color: event.isBusy ? .blue : .gray)
            }
            .foregroundStyle(.primary)
        case .block(let event, let taskID):
            Button { sheetEntry = .event(event, taskID) } label: {
                TimelineLine(time: event.start, title: event.title,
                             detail: CapacityText.duration(Int(event.end.timeIntervalSince(event.start) / 60))
                                 + (model.canEditAsBlock(event) ? " · Zeitblock" : " · verknüpft"),
                             color: .green)
            }
            .foregroundStyle(.primary)
        case .lunch(let start, let minutes):
            Button { sheetEntry = .lunch(day: plan.day, range: start..<(start + minutes)) } label: {
                TimelineLine(time: plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(start * 60)),
                             title: "Mittagspause", detail: CapacityText.duration(minutes), color: .gray)
            }
            .foregroundStyle(.primary)
        case .gap(let range):
            GapLine(text: "frei \(clock(range.lowerBound, on: plan.day))–\(clock(range.upperBound, on: plan.day))")
                .dropDestination(for: String.self) { keys, _ in
                    guard let key = keys.first else { return false }
                    Task { await model.dropTask(key: key, atMinutes: range.lowerBound, on: plan.day) }
                    return true
                }
        }
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) > 80, abs(dx) > 2 * abs(dy) else { return }
            withAnimation(.snappy) { model.step(dx < 0 ? 1 : -1) }
        }
    }

    private func clock(_ minutes: Int, on day: PlanDay) -> String {
        day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Remaining time today (B1) or the day's capacity; opens the working hours of the day.
struct CapacityCard: View {
    let model: PlanningModel
    let plan: DayPlan
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(plan.isPast ? "Vergangen" : CapacityText.remaining(plan.capacity)).font(.headline)
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
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Arbeitszeit an diesem Tag ändern")
    }

    /// "ab jetzt · 13:20 bis 18:00 · ganzer Tag …", or "Arbeitszeit vorbei" after the end of work.
    private func remainingDetail(_ hours: WorkHours) -> String {
        let nowMinutes = Int(model.now().timeIntervalSince(plan.day.startDate(in: model.calendar)) / 60)
        let window = nowMinutes >= hours.endMinutes
            ? "Arbeitszeit vorbei"
            : "ab \(nowMinutes > hours.startMinutes ? "jetzt · " + clock(nowMinutes) : clock(hours.startMinutes))"
                + " bis \(clock(hours.endMinutes))"
        return window + " · ganzer Tag " + CapacityText.summary(plan.capacity)
    }

    private func clock(_ minutes: Int) -> String {
        plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Recurring effort, tasks due today and overdue tasks (both modes; the grid shows planned tasks in its bar).
struct TaskSections: View {
    let model: PlanningModel
    let plan: DayPlan
    var showsPlanned = true
    let onOpenTask: (TaskID) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions

    var body: some View {
        if !plan.recurring.isEmpty {
            Section("Wiederkehrend") {
                ForEach(plan.recurring) { item in
                    Button { onEditRecurring(item, plan.day) } label: {
                        LabeledContent("↻ \(item.title)", value: item.isDone ? "erledigt" : CapacityText.duration(item.minutes))
                            .strikethrough(item.isDone)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        if showsPlanned {
            Section("Geplant ohne Uhrzeit") {
                if plan.assigned.isEmpty {
                    Text("Ziehe Aufgaben in der Woche hierher oder nutze „Einplanen“.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(plan.assigned) { task in taskRow(task, isPastDue: plan.isPastDue.contains(task.id)) }
            }
            if !plan.dueToday.isEmpty {
                Section("Heute fällig") {
                    ForEach(plan.dueToday) { task in taskRow(task, isPastDue: false) }
                }
            }
        }
        if model.anchor == model.today, !model.overdue.isEmpty {
            Section("Von früher offen") {
                ForEach(model.overdue) { task in
                    HStack {
                        Text(task.title)
                        Spacer()
                        Button("Neu einplanen") { onOpenTask(task.id) }.buttonStyle(.borderless)
                        Button("Heute") { Task { await model.assign(task.id, to: model.today) } }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem, isPastDue: Bool) -> some View {
        PlannedTaskRow(task: task, isPastDue: isPastDue)
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
        .accessibilityLabel(text + ", Aufgabe hier ablegen")
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(2)
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
