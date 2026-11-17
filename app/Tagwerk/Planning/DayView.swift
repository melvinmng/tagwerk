import SwiftUI
import TagwerkCore

/// Day view (mockup a): deadline card, capacity, timeline and the day's planned tasks.
struct DayView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    @State private var editingHours = false
    @State private var blockFor: TaskItem?

    var body: some View {
        if let plan = model.days.first {
            List {
                DeadlineCard(deadlines: model.upcomingDeadlines, today: model.today, calendar: model.calendar)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                capacityCard(plan)

                if !model.allDayEvents(for: plan).isEmpty {
                    Section("Ganztägig") {
                        ForEach(model.allDayEvents(for: plan)) { event in
                            Button(event.title) { onOpenEvent(event) }.foregroundStyle(.primary)
                        }
                    }
                }

                Section("Ablauf") {
                    let rows = model.timeline(for: plan)
                    if rows.isEmpty { Text("Keine Termine").foregroundStyle(.secondary) }
                    ForEach(rows) { row in timelineRow(row, plan: plan) }
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
                            .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
                            .swipeActions {
                                Button("Zeitblock") { blockFor = task }.tint(.blue)
                                Button("Ausplanen") { Task { await model.unassign(task.id) } }.tint(.gray)
                            }
                    }
                }

                if !plan.dueToday.isEmpty {
                    Section("Heute fällig") {
                        ForEach(plan.dueToday) { task in
                            PlannedTaskRow(task: task, isPastDue: false)
                                .contentShape(Rectangle())
                                .onTapGesture { onOpenTask(task.id) }
                                .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
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
            .sheet(isPresented: $editingHours) {
                DayOverrideSheet(day: plan.day, calendar: model.calendar,
                                 current: model.workHours(on: plan.day)) { value in
                    model.setDayOverride(value, on: plan.day)
                    Task { await model.reload() }
                }
            }
            .sheet(item: $blockFor) { task in
                BlockSheet(task: task, day: plan.day, hours: model.workHours(on: plan.day), now: model.now(),
                           calendar: model.calendar) { start, minutes in
                    Task { await model.createBlock(for: task, start: start, minutes: minutes) }
                }
            }
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
                if plan.capacity.remainingMinutes != nil {
                    Text("Ganzer Tag: " + CapacityText.summary(plan.capacity)).font(.caption).foregroundStyle(.secondary)
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
            Button { onOpenEvent(event) } label: {
                TimelineLine(time: event.start, title: event.title,
                             detail: CapacityText.duration(Int(event.end.timeIntervalSince(event.start) / 60)) + " · verknüpft",
                             color: .green)
            }
            .foregroundStyle(.primary)
            .contextMenu { Button("Aufgabe öffnen") { onOpenTask(taskID) } }
        case .lunch(let start, let minutes):
            TimelineLine(time: plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(start * 60)),
                         title: "Mittagspause", detail: CapacityText.duration(minutes), color: .gray)
        }
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
