import RemindersKit
import SwiftUI
import TagwerkCore

/// The day in the hour grid (design §13.15): its own scroll view, the "Ohne Uhrzeit" bar to drag tasks onto a
/// time (D1), "Frei" selection (F1), merge suggestions (M1) and the lunch bar (L1).
struct DayGridScreen<Summary: View, Header: View>: View {
    let model: PlanningModel
    let plan: DayPlan
    let onOpenTask: (TaskID) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let timelineHeader: () -> Header
    let onOpenEntry: (DayEntry) -> Void
    let onPlanTask: (TaskItem) -> Void

    @State private var isDragging = false
    @State private var canvasFrame: CGRect = .zero
    @State private var taskDrag: (task: TaskItem, location: CGPoint)?
    @State private var selection: Set<String>?
    @State private var askingSeriesFree: Bool?
    @State private var pendingSeriesCommit: CanvasCommit?
    @State private var lunchChanged = false
    /// The break as just set by dragging (shown before the model has reloaded).
    @State private var changedLunch: Range<Int>?
    @State private var alwaysMerge: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summary()
                ForEach(daySuggestions) { suggestion in mergeCard(suggestion) }
                HStack {
                    timelineHeader()
                    Button(selection == nil ? "Auswählen" : "Fertig") {
                        selection = selection == nil ? [] : nil
                    }
                    .font(.subheadline)
                }
                canvas
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("screen")) } action: { canvasFrame = $0 }
                VStack(alignment: .leading, spacing: 8) {
                    TaskSections(model: model, plan: plan, showsPlanned: false, onOpenTask: onOpenTask,
                                 onEditRecurring: onEditRecurring, menuActions: menuActions)
                }
                Color.clear.frame(height: 140)  // room for the bottom bar
            }
            .padding(.horizontal)
        }
        .scrollDisabled(isDragging || taskDrag != nil)
        .simultaneousGesture(daySwipe)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if lunchChanged { lunchBar }
                if selection != nil { selectionBar } else { unscheduledBar }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .confirmationDialog("Dieser Termin wiederholt sich", isPresented: hasSeriesCommit, titleVisibility: .visible,
                            presenting: pendingSeriesCommit) { commit in
            Button("Nur diesen Termin") { write(commit, span: .thisEvent) }
            Button("Diesen und alle folgenden") { write(commit, span: .futureEvents) }
            Button("Abbrechen", role: .cancel) { Task { await model.reload() } }
        }
        // Outermost, so the grid and the bottom bar measure in the same space.
        .coordinateSpace(.named("screen"))
        .confirmationDialog("Darunter sind Serientermine", isPresented: hasSeriesFree, titleVisibility: .visible) {
            Button("Nur an diesem Tag") { applyFree(series: false) }
            Button("Auch alle künftigen Termine dieser Serien") { applyFree(series: true) }
        }
    }

    // MARK: Canvas

    private var entries: [DayEntry] {
        var result: [DayEntry] = plan.events.filter { !$0.isAllDay }.map { .event($0, nil) }
        result += plan.blocks.map { .event($0, plan.links[$0.id]) }
        if !plan.capacity.isDayOff, let lunch = model.lunch(on: plan.day) {
            result.append(.lunch(day: plan.day, range: lunch))
        }
        return result
    }

    private var canvas: TimelineCanvas {
        TimelineCanvas(model: model, plan: plan, entries: entries, selectingIDs: selection, taskPreview: taskPreview,
                       onTap: onOpenEntry, onToggleSelection: toggle, onCommit: commit, isDragging: $isDragging)
    }

    private func commit(_ change: CanvasCommit) {
        switch change.entry {
        case .lunch(let day, _):
            Task { await model.setLunch(startMinutes: change.range.lowerBound, minutes: change.range.count, on: day) }
            changedLunch = snapped(minutes: change.range.lowerBound)..<snapped(minutes: change.range.upperBound)
            withAnimation { lunchChanged = true }
        case .event(let event, _):
            if event.isRecurring { pendingSeriesCommit = change } else { write(change, span: .thisEvent) }
        }
    }

    private func write(_ change: CanvasCommit, span: EventSpan) {
        guard case .event(let event, _) = change.entry else { return }
        Task { await model.setTime(of: event, startMinutes: change.range.lowerBound, endMinutes: change.range.upperBound, span: span) }
    }

    private var hasSeriesCommit: Binding<Bool> {
        Binding(get: { pendingSeriesCommit != nil }, set: { if !$0 { pendingSeriesCommit = nil } })
    }

    // MARK: "Ohne Uhrzeit" (D1)

    private var unplannedToday: [TaskItem] { model.timelessTasks(for: plan) }

    @ViewBuilder
    private var unscheduledBar: some View {
        if !unplannedToday.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ohne Uhrzeit").font(.subheadline.weight(.semibold))
                    Text("\(unplannedToday.count) · halten und ins Raster ziehen").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(unplannedToday) { task in chip(task) }
                    }
                }
                .scrollDisabled(taskDrag != nil)
            }
            .padding(10)
            .background(.bar, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func chip(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(task.title).font(.subheadline).lineLimit(1)
            Text(CapacityText.duration(model.suggestedBlockMinutes(for: task))).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .opacity(taskDrag?.task.id == task.id ? 0.4 : 1)
        .onTapGesture { onPlanTask(task) }
        .gesture(LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("screen")))
            .onChanged { value in
                if case .second(true, let drag?) = value { taskDrag = (task, drag.location) }
            }
            .onEnded { value in
                defer { taskDrag = nil }
                guard case .second(true, let drag?) = value, canvasFrame.contains(drag.location) else { return }
                let minutes = canvas.minutes(atY: drag.location.y - canvasFrame.minY)
                Task { await model.dropTask(key: task.id.key, atMinutes: minutes, on: plan.day) }
            })
        .sensoryFeedback(.impact(weight: .light), trigger: taskDrag?.task.id) { _, new in new != nil }
        .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
        .accessibilityHint("Antippen plant eine Uhrzeit, halten und ziehen legt sie im Raster fest")
    }

    /// The dragged task as a to-scale block at the finger's time (only over the grid).
    private var taskPreview: (title: String, startMinutes: Int, minutes: Int)? {
        guard let taskDrag, canvasFrame.contains(taskDrag.location) else { return nil }
        let base = TimelineCanvas(model: model, plan: plan, entries: entries, selectingIDs: nil, taskPreview: nil,
                                  onTap: { _ in }, onToggleSelection: { _ in }, onCommit: { _ in }, isDragging: .constant(false))
        return (taskDrag.task.title, base.minutes(atY: taskDrag.location.y - canvasFrame.minY),
                model.suggestedBlockMinutes(for: taskDrag.task))
    }

    // MARK: "Frei" selection (F1)

    private func toggle(_ event: CalendarEvent) {
        guard var current = selection else { return }
        if current.contains(event.id) { current.remove(event.id) } else { current.insert(event.id) }
        selection = current
    }

    private var selectedEvents: [CalendarEvent] {
        guard let selection else { return [] }
        return (plan.events + plan.blocks).filter { selection.contains($0.id) }
    }

    private var selectionBar: some View {
        let events = selectedEvents
        return VStack(alignment: .leading, spacing: 8) {
            Text(events.isEmpty ? "Termine antippen, um sie auszuwählen"
                 : "\(events.count) ausgewählt · „Frei“ gibt \(CapacityText.duration(model.busyMinutes(of: events))) frei")
                .font(.subheadline)
            HStack {
                Button("Alle Termine") { selection = Set(plan.events.filter { !$0.isAllDay }.map(\.id)) }
                Spacer()
                Button("Belegt") { askOrApplyFree(free: false) }.buttonStyle(.bordered).disabled(events.isEmpty)
                Button("Auf Frei setzen") { askOrApplyFree(free: true) }.buttonStyle(.borderedProminent).disabled(events.isEmpty)
            }
        }
        .padding(12)
        .background(.bar, in: RoundedRectangle(cornerRadius: 16))
    }

    private func askOrApplyFree(free: Bool) {
        if selectedEvents.contains(where: \.isRecurring) { askingSeriesFree = free } else { applyFree(series: false, free: free) }
    }

    private func applyFree(series: Bool, free: Bool? = nil) {
        let value = free ?? askingSeriesFree ?? true
        let events = selectedEvents
        askingSeriesFree = nil
        selection = nil
        Task { await model.setFree(events, free: value, series: series) }
    }

    private var hasSeriesFree: Binding<Bool> {
        Binding(get: { askingSeriesFree != nil }, set: { if !$0 { askingSeriesFree = nil } })
    }

    // MARK: Lunch bar (L1) and merge suggestions (M1)

    private var lunchBar: some View {
        HStack {
            let range = changedLunch ?? model.lunch(on: plan.day)
            Text(range.map { "Pause heute \(clock($0.lowerBound))–\(clock($0.upperBound))" } ?? "Heute keine Pause")
                .font(.subheadline)
            Spacer()
            Button("Für alle Tage") {
                Task { await model.applyLunchToAllDays(from: plan.day) }
                withAnimation { lunchChanged = false }
            }
            .buttonStyle(.bordered)
            Button("Widerrufen") {
                Task { await model.resetLunch(on: plan.day) }
                withAnimation { lunchChanged = false }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.bar, in: RoundedRectangle(cornerRadius: 16))
        .task(id: lunchChanged) {
            guard lunchChanged else { return }
            try? await Task.sleep(for: .seconds(8))
            withAnimation { lunchChanged = false }
        }
    }

    private var daySuggestions: [MergeSuggestion] {
        let ids = Set((plan.events + plan.blocks).map(\.id))
        return model.mergeSuggestions.filter { ids.contains($0.placeholderID) && ids.contains($0.keptID) }
    }

    private func mergeCard(_ suggestion: MergeSuggestion) -> some View {
        let kept = (plan.events + plan.blocks).first { $0.id == suggestion.keptID }
        let calendarName = model.calendarTitle(suggestion.placeholderCalendarID) ?? "Kalender"
        return VStack(alignment: .leading, spacing: 8) {
            Label("Derselbe Termin?", systemImage: "rectangle.on.rectangle").font(.subheadline.weight(.semibold))
            Text("„\(suggestion.placeholderTitle)“ aus „\(calendarName)“ liegt zur selben Zeit wie „\(kept?.title ?? "")“.")
                .font(.subheadline).foregroundStyle(.secondary)
            Toggle("Künftig immer bei „\(suggestion.placeholderTitle)“ aus „\(calendarName)“",
                   isOn: Binding(get: { alwaysMerge.contains(suggestion.id) },
                                 set: { on in if on { alwaysMerge.insert(suggestion.id) } else { alwaysMerge.remove(suggestion.id) } }))
                .font(.caption)
            HStack {
                Button("Getrennt lassen") {
                    Task { await model.decideMerge(suggestion, merge: false, always: alwaysMerge.contains(suggestion.id)) }
                }
                .buttonStyle(.bordered)
                Button("Zusammenfassen") {
                    Task { await model.decideMerge(suggestion, merge: true, always: alwaysMerge.contains(suggestion.id)) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Helpers

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard !isDragging, taskDrag == nil else { return }
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) > 80, abs(dx) > 2 * abs(dy) else { return }
            withAnimation(.snappy) { model.step(dx < 0 ? 1 : -1) }
        }
    }

    private func clock(_ minutes: Int) -> String {
        plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}
