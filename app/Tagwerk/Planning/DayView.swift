import SwiftUI
import TagwerkCore

/// Day view (mockup a): deadline card, capacity, timeline and the day's planned tasks.
struct DayView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let onShowTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    @State private var editingHours = false
    @State private var blockFor: TaskItem?
    @State private var movingBlock: CalendarEvent?
    @State private var blockActions: CalendarEvent?
    @State private var showsGrid = false

    var body: some View {
        if let plan = model.days.first {
            List {
                DayHeader(model: model) { model.scope = .month }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                Section {
                    DeadlineCard(deadlines: model.upcomingDeadlines, today: model.today, calendar: model.calendar)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section { capacityCard(plan) }

                if !model.allDayEvents(for: plan).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("Ganztägig").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(model.allDayEvents(for: plan)) { event in
                                Button { onOpenEvent(event) } label: {
                                    Text(event.title).font(.subheadline).lineLimit(1)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(.thinMaterial, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    if showsGrid {
                        HourGrid(model: model, plan: plan, onOpenEvent: onOpenEvent) { block in blockActions = block }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    } else {
                        let rows = model.timelineWithGaps(for: plan)
                        if rows.isEmpty { Text("Keine Termine").foregroundStyle(.secondary) }
                        ForEach(rows) { row in timelineRow(row, plan: plan) }
                    }
                } header: {
                    HStack {
                        Text("Ablauf")
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

                Section("Geplant ohne Uhrzeit") {
                    if plan.assigned.isEmpty {
                        Text("Ziehe Aufgaben in der Woche hierher oder nutze „Einplanen“.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(plan.assigned) { task in
                        PlannedTaskRow(task: task, isPastDue: plan.isPastDue.contains(task.id))
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenTask(task.id) }
                            .contextMenu { TaskContextMenu(item: task, actions: plannedActions(task)) }
                    }
                }

                if !plan.dueToday.isEmpty {
                    Section("Heute fällig") {
                        ForEach(plan.dueToday) { task in
                            PlannedTaskRow(task: task, isPastDue: false)
                                .contentShape(Rectangle())
                                .onTapGesture { onOpenTask(task.id) }
                                .contextMenu { TaskContextMenu(item: task, actions: plannedActions(task, canUnassign: false)) }
                        }
                    }
                }

                if model.anchor == model.today, !model.overdue.isEmpty {
                    Section("Von früher offen") {
                        ForEach(model.overdue) { task in
                            HStack {
                                Text(task.title)
                                Spacer()
                                Button("Neu einplanen") { onOpenTask(task.id) }
                                    .buttonStyle(.borderless)
                                Button("Heute") { Task { await model.assign(task.id, to: model.today) } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            // Horizontal swipes change the day (mockup A1); vertical scrolling stays with the list.
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > 2 * abs(dy) else { return }
                withAnimation(.snappy) { model.step(dx < 0 ? 1 : -1) }
            })
            .sheet(isPresented: $editingHours) {
                DayOverrideSheet(day: plan.day, calendar: model.calendar,
                                 current: model.workHours(on: plan.day)) { value in
                    model.setDayOverride(value, on: plan.day)
                    Task { await model.reload() }
                }
            }
            .onAppear { showsGrid = model.showsHourGrid }
            .confirmationDialog(blockActions?.title ?? "", isPresented: hasBlockActions, titleVisibility: .visible,
                                presenting: blockActions) { block in
                blockDialogButtons(block, plan: plan)
            }
            .sheet(item: $movingBlock) { block in BlockDaySheet(block: block, model: model) }
            .sheet(item: $blockFor) { task in
                BlockSheet(task: task, day: plan.day, hours: model.workHours(on: plan.day), now: model.now(),
                           minutes: model.suggestedBlockMinutes(for: task),
                           calendar: model.calendar) { start, minutes in
                    Task { await model.createBlock(for: task, start: start, minutes: minutes) }
                }
            }
        } else {
            // Keeps a view in place before the first load; otherwise the parent's `.task` would never run.
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func capacityCard(_ plan: DayPlan) -> some View {
        Button { editingHours = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(plan.isPast ? "Vergangen" : CapacityText.remaining(plan.capacity)).font(.headline)
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }
                if plan.capacity.remainingMinutes != nil, let hours = model.workHours(on: plan.day) {
                    Text(remainingDetail(hours, plan: plan)).font(.caption).foregroundStyle(.secondary)
                }
                CapacityBar(capacity: plan.capacity)
                if plan.capacity.estimatedCount > 0 {
                    Text("\(plan.capacity.estimatedCount) Aufgabe(n) ohne Aufwand mit Standarddauer gerechnet")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Arbeitszeit an diesem Tag ändern")
    }

    private var hasBlockActions: Binding<Bool> {
        Binding(get: { blockActions != nil }, set: { if !$0 { blockActions = nil } })
    }

    /// The block menu's actions as dialog buttons (hour grid, mockup C1).
    @ViewBuilder
    private func blockDialogButtons(_ block: CalendarEvent, plan: DayPlan) -> some View {
        let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
        let start = Int(block.start.timeIntervalSince(plan.day.startDate(in: model.calendar)) / 60)
        Button("15 min früher") { Task { await model.moveBlock(block, toStartMinutes: start - 15, on: plan.day) } }
        Button("15 min später") { Task { await model.moveBlock(block, toStartMinutes: start + 15, on: plan.day) } }
        if minutes > 15 {
            Button("15 min kürzer") { Task { await model.resizeBlock(block, minutes: minutes - 15) } }
        }
        Button("15 min länger") { Task { await model.resizeBlock(block, minutes: minutes + 15) } }
        Button("Auf anderen Tag …") { movingBlock = block }
        if let taskID = plan.links[block.id] { Button("Aufgabe zeigen") { onShowTask(taskID) } }
        Button("Zeitblock löschen", role: .destructive) { Task { await model.deleteBlock(block) } }
    }

    private func blockMenu(_ block: CalendarEvent, _ taskID: TaskID) -> BlockMenu {
        BlockMenu(block: block, taskID: taskID, model: model, onShowTask: onShowTask) { movingBlock = $0 }
    }

    /// The shared menu plus the day-only entries that replaced the swipe actions.
    private func plannedActions(_ task: TaskItem, canUnassign: Bool = true) -> TaskMenuActions {
        var actions = menuActions(task)
        actions.createBlock = { blockFor = task }
        if canUnassign { actions.unassign = { Task { await model.unassign(task.id) } } }
        return actions
    }

    /// "ab jetzt · 13:20 bis 18:00 · ganzer Tag …", or "Arbeitszeit vorbei" after the end of work.
    private func remainingDetail(_ hours: WorkHours, plan: DayPlan) -> String {
        let nowMinutes = Int(model.now().timeIntervalSince(plan.day.startDate(in: model.calendar)) / 60)
        let window = nowMinutes >= hours.endMinutes
            ? "Arbeitszeit vorbei"
            : "ab \(nowMinutes > hours.startMinutes ? "jetzt · " + clock(nowMinutes, on: plan.day) : clock(hours.startMinutes, on: plan.day))"
                + " bis \(clock(hours.endMinutes, on: plan.day))"
        return window + " · ganzer Tag " + CapacityText.summary(plan.capacity)
    }

    private func clock(_ minutes: Int, on day: PlanDay) -> String {
        day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow, plan: DayPlan) -> some View {
        switch row {
        case .event(let event):
            Button { onOpenEvent(event) } label: {
                TimelineLine(time: event.start, title: event.title,
                             detail: "bis \(event.end.formatted(date: .omitted, time: .shortened))"
                                 + (event.mergedCalendarIDs.isEmpty ? "" : " · \(event.mergedCalendarIDs.count + 1) Kalender"),
                             color: .blue)
            }
            .foregroundStyle(.primary)
        case .block(let event, let taskID):
            let line = TimelineLine(time: event.start, title: event.title,
                                    detail: CapacityText.duration(Int(event.end.timeIntervalSince(event.start) / 60))
                                        + (model.canEditAsBlock(event) ? " · Zeitblock" : " · verknüpft"),
                                    color: .green)
            if model.canEditAsBlock(event) {
                Menu { blockMenu(event, taskID) } label: { line }.foregroundStyle(.primary)
            } else {
                // Linked events of other calendars keep the event detail (series question, read-only notice).
                Button { onOpenEvent(event) } label: { line }.foregroundStyle(.primary)
            }
        case .gap(let range):
            GapLine(text: "frei \(clock(range.lowerBound, on: plan.day))–\(clock(range.upperBound, on: plan.day))")
                .dropDestination(for: String.self) { keys, _ in
                    guard let key = keys.first else { return false }
                    Task { await model.dropTask(key: key, atMinutes: range.lowerBound, on: plan.day) }
                    return true
                }
        case .lunch(let start, let minutes):
            TimelineLine(time: plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(start * 60)),
                         title: "Mittagspause", detail: CapacityText.duration(minutes), color: .gray)
        }
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
