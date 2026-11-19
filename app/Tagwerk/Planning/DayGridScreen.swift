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
    /// Panel "Ohne Uhrzeit" (design §13.15 D1, reworked after device feedback 2026-11-18).
    @SceneStorage("tagwerk.dayPanelExpanded") private var panelExpanded = false
    @State private var scrollFrame: CGRect = .zero
    @State private var panelHeaderMinY: CGFloat = .greatestFiniteMagnitude
    @State private var panelBodyHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var contentOffsetY: CGFloat = 0
    /// -1 scrolls up, 1 down while a dragged task is near the edge of the visible grid.
    @State private var edgeScroll = 0
    @State private var drops = 0
    /// The day whose grid is being aligned to the current time, until `nowAlignmentEnds` or the first touch scroll.
    /// The content above the grid can still grow while it loads, so the alignment repeats in that window only.
    @State private var canvasTopInContent: CGFloat = 0
    @State private var nowAlignedDay: PlanDay?
    @State private var nowAlignmentEnds = Date.distantPast
    @State private var userScrolled = false

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
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("gridContent")).minY } action: { canvasTopInContent = $0 }
            }
            .padding(.horizontal)
            .coordinateSpace(.named("gridContent"))
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in contentOffsetY = offset }
        .onScrollPhaseChange { _, phase in if phase == .interacting { userScrolled = true } }
        .contentMargins(.bottom, 80, for: .scrollContent)  // room for the collapsed panel
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("screen")) } action: { scrollFrame = $0 }
        .scrollDisabled(isDragging || taskDrag != nil)
        .simultaneousGesture(pageSwipeGesture { model.step($0.step) })
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if lunchChanged { lunchBar }
                if selection != nil { selectionBar } else { dayPanel }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .task(id: OpenKey(day: plan.day, canvasTop: Int(canvasTopInContent.rounded()), isMeasured: canvasFrame.height > 0 && scrollFrame.height > 0)) {
            scrollToNowOnOpening()
        }
        .task(id: edgeScroll) {
            // Scrolls the grid while a dragged task rests near its top or bottom edge.
            guard edgeScroll != 0 else { return }
            while !Task.isCancelled {
                scrollPosition.scrollTo(y: max(0, contentOffsetY + CGFloat(edgeScroll * 6)))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taskDrag?.task.id) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: taskPreview.map { snapped(minutes: $0.startMinutes) })
        .sensoryFeedback(.impact(weight: .medium), trigger: drops)
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

    // MARK: Current time

    private struct OpenKey: Equatable {
        let day: PlanDay
        /// Grid top in the scroll content, rounded: changes when the content above it grows.
        let canvasTop: Int
        let isMeasured: Bool
    }

    /// Opening today puts the current time at a third of the visible height. It repeats while the content above
    /// the grid is still loading (a few seconds at most) and stops at the first scroll by the user.
    private func scrollToNowOnOpening() {
        guard plan.day == model.today, canvasFrame.height > 0, scrollFrame.height > 0,
              let minutes = NowMarker.minutes(now: model.now(), day: plan.day, calendar: model.calendar) else { return }
        if nowAlignedDay != plan.day {
            nowAlignedDay = plan.day
            nowAlignmentEnds = Date.now.addingTimeInterval(3)
            userScrolled = false
        }
        guard Date.now < nowAlignmentEnds, !userScrolled else { return }
        let shown = canvas.shownRange
        guard NowMarker.position(nowMinutes: minutes, shown: shown) != nil else { return }
        let target = NowMarker.scrollTarget(nowMinutes: minutes, shown: shown, hourHeight: Double(TimelineCanvas.hourHeight),
                                            inset: Double(TimelineCanvas.lineInset), canvasTop: Double(canvasTopInContent),
                                            viewportHeight: Double(scrollFrame.height))
        scrollPosition.scrollTo(y: CGFloat(target))
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

    // MARK: Panel "Ohne Uhrzeit" (D1)

    /// Tasks with blocks but less time than their effort (mockup RZ1), shown today and on future days.
    private var toSchedule: [TaskItem] { plan.day >= model.today ? model.toSchedule : [] }
    private var toScheduleIDs: Set<TaskID> { Set(toSchedule.map(\.id)) }
    /// Today and tomorrow only (plan-tomorrow, decision 3).
    private var overdueToday: [TaskItem] {
        model.showsOverdue(on: plan.day) ? model.overdue.filter { !toScheduleIDs.contains($0.id) } : []
    }
    private var openToday: [TaskItem] { plan.openToday.filter { !toScheduleIDs.contains($0.id) } }
    /// "Von heute übrig" on the next planning day once today is over (MP2).
    private var leftovers: [TaskItem] { model.leftovers(on: plan.day).filter { !toScheduleIDs.contains($0.id) } }
    private var commitTitle: String { DayPanelText.commitTitle(day: plan.day, today: model.today, calendar: model.calendar) }

    /// "Noch einzuplanen", planned tasks, "Von heute übrig", tasks due on the day and "Überfällig"; rows drag by
    /// their grip onto the grid.
    @ViewBuilder
    private var dayPanel: some View {
        let planned = model.timelessTasks(for: plan).filter { !toScheduleIDs.contains($0.id) }
        if !(planned.isEmpty && openToday.isEmpty && overdueToday.isEmpty && toSchedule.isEmpty && leftovers.isEmpty) {
            let dragging = taskDrag != nil
            VStack(spacing: 0) {
                panelHeader(planned)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("screen")).minY } action: { panelHeaderMinY = $0 }
                if panelExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            panelSection(String(localized: "Noch einzuplanen"), toSchedule, commit: nil)
                            panelSection(String(localized: "Ohne Uhrzeit"), planned, commit: nil)
                            leftoverSection
                            panelSection(DayPanelText.dueSectionTitle(day: plan.day, today: model.today, calendar: model.calendar),
                                         openToday, commit: .assign)
                            panelSection(String(localized: "Überfällig"), overdueToday, commit: .assign, isOverdue: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                    .scrollDisabled(dragging)
                    .frame(maxHeight: max(160, scrollFrame.height * 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelBodyHeight = $0 }
                    .opacity(dragging ? 0 : 1)
                }
            }
            .background(.bar, in: RoundedRectangle(cornerRadius: 16))
            // Moves sit at their task rows, so the panel opens when there are any (proposal §5).
            .onChange(of: moveSuggestions.count) { _, count in if count > 0 { panelExpanded = true } }
            // While dragging, the panel slides down to its header so the grid behind is free; the dragged row
            // stays in the hierarchy so its gesture keeps running.
            .offset(y: dragging && panelExpanded ? panelBodyHeight : 0)
            .animation(.snappy(duration: 0.2), value: dragging)
        }
    }

    private func panelHeader(_ planned: [TaskItem]) -> some View {
        let minutes = planned.reduce(0) { $0 + model.suggestedBlockMinutes(for: $1) }
        return Button {
            withAnimation(.snappy) { panelExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                if !toSchedule.isEmpty {
                    let rest = toSchedule.compactMap { model.sessionProgress[$0.id]?.remaining }.reduce(0, +)
                    Text("Rest \(CapacityText.duration(rest))").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                }
                Text("Ohne Uhrzeit").font(.subheadline.weight(.semibold))
                Text(toSchedule.isEmpty ? "\(planned.count) · \(CapacityText.duration(minutes))" : "\(planned.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !openToday.isEmpty {
                    Text(toSchedule.isEmpty ? "+\(openToday.count) offen" : "+\(openToday.count)").font(.caption).foregroundStyle(.secondary)
                }
                if !leftovers.isEmpty {
                    Text("\(leftovers.count) von heute").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                if !overdueToday.isEmpty {
                    Text("\(overdueToday.count) überfällig").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: panelExpanded ? "chevron.down" : "chevron.up").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(panelExpanded ? "Liste einklappen" : "Liste aufklappen")
    }

    /// What the row button does: commit the task to the shown day, or move it there with its blocks (leftovers).
    private enum Commit { case assign, move }

    @ViewBuilder
    private func panelSection(_ title: String, _ tasks: [TaskItem], commit: Commit?, isOverdue: Bool = false) -> some View {
        if !tasks.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(isOverdue ? .orange : .secondary)
                .padding(.top, 8).padding(.bottom, 2)
            ForEach(tasks) { task in panelRow(task, commit: commit, isOverdue: isOverdue) }
        }
    }

    /// "Von heute übrig" with "Alle auf morgen"; moving keeps blocks and offers "Widerrufen" (MP2).
    @ViewBuilder
    private var leftoverSection: some View {
        let tasks = leftovers
        if !tasks.isEmpty {
            HStack {
                Text("Von heute übrig").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                Spacer()
                Button(DayPanelText.moveAllTitle(day: plan.day, today: model.today, calendar: model.calendar)) {
                    let day = plan.day
                    Task { await model.moveTasks(tasks.map(\.id), to: day) }
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.top, 8).padding(.bottom, 2)
            ForEach(tasks) { task in panelRow(task, commit: .move, isOverdue: false) }
        }
    }

    /// Pending moves of this day by task key (proposal §5).
    private var moveSuggestions: [String: PlanSuggestion] {
        Dictionary(plan.suggestions.filter { $0.kind == .move }.map { ($0.taskKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @ViewBuilder
    private func panelRow(_ task: TaskItem, commit: Commit?, isOverdue: Bool) -> some View {
        if let move = moveSuggestions[task.id.key] {
            MoveSuggestionRow(suggestion: move)
        } else {
            plainPanelRow(task, commit: commit, isOverdue: isOverdue)
        }
    }

    private func plainPanelRow(_ task: TaskItem, commit: Commit?, isOverdue: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline).lineLimit(2)
                Text(rowDetails(task, isOverdue: isOverdue)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let progress = model.sessionProgress[task.id], toScheduleIDs.contains(task.id) {
                Text("noch \(CapacityText.duration(progress.remaining))").font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            if let priority = task.priority {
                Text(priority.label).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priority == .p1 ? Color.red.opacity(0.25) : Color.secondary.opacity(0.2), in: Capsule())
            }
            if let commit {
                Button(commitTitle) {
                    let day = plan.day
                    Task {
                        switch commit {
                        case .assign: await model.commitToShownDay(task.id)
                        case .move: await model.moveTask(task.id, to: day)
                        }
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            grip(task)
        }
        .padding(.leading, 4)
        .opacity(taskDrag?.task.id == task.id ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onPlanTask(task) }
        .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
    }

    /// Effort (or reserved recurring effort) · due · ↻ · source.
    private func rowDetails(_ task: TaskItem, isOverdue: Bool) -> String {
        var parts: [String] = []
        if let progress = model.sessionProgress[task.id] {
            // Mockup FS1: what is planned against the effort.
            parts.append(String(localized: "\(CapacityText.duration(progress.blocked)) von \(CapacityText.duration(progress.estimate)) eingeplant"))
        } else if let recurring = model.recurringItem(for: task, on: plan.day) {
            parts.append(recurring.minutes > 0 ? String(localized: "↻ \(CapacityText.duration(recurring.minutes)) reserviert") : "↻")
        } else {
            parts.append(CapacityText.duration(model.suggestedBlockMinutes(for: task)))
        }
        if let due = task.due {
            parts.append(String(localized: "fällig \(DueText.text(due, now: model.now(), calendar: model.calendar))"))
        } else if isOverdue, let planned = model.planStore.assignment(for: task.id) {
            parts.append(String(localized: "geplant \(planned.startDate(in: model.calendar).formatted(.dateTime.weekday(.abbreviated).day().month()))"))
        }
        parts.append(task.container.name)
        return parts.joined(separator: " · ")
    }

    /// Drags at once (no hold), so the list itself keeps scrolling; the preview starts after 8 pt.
    private func grip(_ task: TaskItem) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("screen"))
                .onChanged { value in
                    if taskDrag == nil, hypot(value.translation.width, value.translation.height) < 8 { return }
                    taskDrag = (task, value.location)
                    edgeScroll = edgeDirection(at: value.location)
                }
                .onEnded { value in
                    defer {
                        taskDrag = nil
                        edgeScroll = 0
                    }
                    guard taskDrag != nil, isDropZone(value.location) else { return }
                    let minutes = canvasMinutes(atY: value.location.y)
                    drops += 1
                    Task { await model.dropTask(key: task.id.key, atMinutes: minutes, on: plan.day) }
                })
            .accessibilityLabel("Ins Raster ziehen")
            .accessibilityAction(named: "Uhrzeit wählen") { onPlanTask(task) }
    }

    /// Top of the panel while dragging (it has slid down to its header).
    private var dropLimitY: CGFloat {
        panelHeaderMinY + (taskDrag != nil && panelExpanded ? panelBodyHeight : 0)
    }

    /// Only the visible part of the grid above the panel accepts a drop; the panel's header cancels.
    private func isDropZone(_ point: CGPoint) -> Bool {
        canvasFrame.contains(point) && scrollFrame.contains(point) && point.y < dropLimitY
    }

    private func edgeDirection(at point: CGPoint) -> Int {
        if point.y > dropLimitY - 60 { return 1 }
        if point.y < scrollFrame.minY + 60 { return -1 }
        return 0
    }

    private func canvasMinutes(atY y: CGFloat) -> Int {
        let base = TimelineCanvas(model: model, plan: plan, entries: entries, selectingIDs: nil, taskPreview: nil,
                                  onTap: { _ in }, onToggleSelection: { _ in }, onCommit: { _ in }, isDragging: .constant(false))
        return base.minutes(atY: y - canvasFrame.minY)
    }

    /// The dragged task as a to-scale block at the finger's time (only over the visible grid).
    private var taskPreview: (title: String, startMinutes: Int, minutes: Int)? {
        guard let taskDrag, isDropZone(taskDrag.location) else { return nil }
        let task = taskDrag.task
        let minutes = model.suggestedBlockMinutes(for: task, on: plan.day)
        // Mockup ZV1: the preview names the time still open.
        let title = model.sessionProgress[task.id].map { String(localized: "\(task.title) · Rest \(CapacityText.duration($0.remaining))") } ?? task.title
        return (title, canvasMinutes(atY: taskDrag.location.y), minutes)
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
            Text(DayPanelText.lunchLine(range, day: plan.day, today: model.today, calendar: model.calendar))
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
}
