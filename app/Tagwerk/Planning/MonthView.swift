import SwiftUI
import TagwerkCore

/// Month view (mockup c-A): load bar per day, deadline days filled red, deadline list below.
struct MonthView: View {
    @Bindable var model: PlanningModel
    let onSelectDay: (PlanDay) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onOpenTask: (TaskID) -> Void
    let deadlineActions: DeadlineActions
    @State private var newEventDay: PlanDay?
    @State private var hoursDay: PlanDay?
    @State private var planningDay: PlanDay?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            AIPlanBar(scope: .month)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.bottom, 8)
            // The container wraps only the grid: the vertical scroll view stays the one the navigation bar tracks, and the
            // swipe over the day below keeps stepping the selected day.
            PagedContainer(canGoBack: true, canGoForward: true, isLocked: false, contentID: { model.days.first?.day },
                           sizesToCurrentPage: true,
                           onPage: { model.step($0.step) }, onPrevailingPage: { model.titlePreviewStep = $0?.step },
                           onBlockedEdge: {}) { slot in
                switch slot {
                case .current: monthGrid
                case .previous: monthPreview(step: -1)
                case .next: monthPreview(step: 1)
                case .arrived: MonthPagePreview(model: model, anchor: model.anchor)
                }
            }

            if let plan = model.days.first(where: { $0.day == model.monthSelection }) {
                MonthDayDetail(model: model, plan: plan, onOpenDay: { onSelectDay(plan.day) },
                               onOpenEvent: onOpenEvent, onOpenTask: onOpenTask, deadlineActions: deadlineActions)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                    .simultaneousGesture(pageSwipeGesture { model.stepSelectedDay($0.step) })  // over the day: the day
            }

            let deadlines = model.days.flatMap(\.deadlines)
            if !deadlines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deadlines").font(.headline)
                    ForEach(deadlines) { deadline in
                        HStack {
                            Text(deadline.day.startDate(in: model.calendar).formatted(.dateTime.day().month()))
                                .font(.caption.monospacedDigit()).frame(width: 52, alignment: .leading)
                            DeadlineLine(deadline: deadline)
                        }
                        .deadlineInteractions(deadline, model: model, actions: deadlineActions)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: model.unplanned.isEmpty ? 0 : 56) }
        .overlay(alignment: .bottom) { UnplannedDrawer(model: model) }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $newEventDay) { day in EventEditSheet(model: model, existing: nil, day: day) }
        .sheet(item: $hoursDay) { day in
            DayOverrideSheet(day: day, calendar: model.calendar, current: model.workHours(on: day)) { value in
                model.setDayOverride(value, on: day)
                Task { await model.reload() }
            }
        }
        .sheet(item: $planningDay) { day in PlanTaskPicker(model: model, day: day) }
    }

    /// Weekday header and the days of the shown month, with load bars and marks.
    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(DateText.shortStandaloneWeekdaySymbols(calendar: model.calendar), id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondaryText) }
            ForEach(model.days) { plan in
                // First tap selects the day (mockup E1); a second tap opens it in "Tag".
                Button {
                    if model.monthSelection == plan.day { onSelectDay(plan.day) } else { model.selectedDay = plan.day }
                } label: { cell(plan) }
                    .buttonStyle(.plain)
                    .contextMenu { dayMenu(plan.day) }
                    .dropDestination(for: String.self) { keys, _ in
                        let ids = keys.compactMap(TaskID.init(key:))
                        Task { for id in ids { await model.assign(id, to: plan.day) } }
                        return !ids.isEmpty
                    }
            }
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
    }

    /// The month before or after the shown one, as a plain page.
    private func monthPreview(step: Int) -> some View {
        MonthPagePreview(model: model, anchor: PlanHeaderText.shiftedAnchor(scope: .month, anchor: model.anchor, step: step,
                                                                          calendar: model.calendar))
    }

    @ViewBuilder
    private func dayMenu(_ day: PlanDay) -> some View {
        Button("Tag öffnen", systemImage: "calendar.day.timeline.left") { onSelectDay(day) }
        Button("Aufgabe hier einplanen …", systemImage: "calendar.badge.plus") { planningDay = day }
        Button("Neuer Termin", systemImage: "plus") { newEventDay = day }
        Button("Arbeitszeit an diesem Tag …", systemImage: "clock") { hoursDay = day }
    }

    private func cell(_ plan: DayPlan) -> some View {
        let inMonth = plan.day.month == model.anchor.month
        let hasDeadline = !plan.deadlines.isEmpty
        return VStack(spacing: 4) {
            Text("\(plan.day.day)")
                .font(.callout.weight(plan.day == model.today ? .bold : .regular))
                .foregroundStyle(hasDeadline ? .white : (inMonth ? Color.primary : Color.secondaryText))
            CapacityBar(capacity: plan.capacity).frame(width: 28)
                .overlay(alignment: .topTrailing) {
                    // Open AI suggestions on this day (mockup X2).
                    if plan.suggestions.contains(where: { $0.kind == .dayChange }) {
                        // Mockup AO1: a longer day is suggested here.
                        Image(systemName: "clock.badge").font(.system(size: 8)).foregroundStyle(.purple).offset(x: 10, y: -10)
                    } else if plan.suggestions.contains(where: { $0.kind == .move }) {
                        Image(systemName: "arrow.uturn.right").font(.system(size: 8)).foregroundStyle(.purple).offset(x: 10, y: -10)
                    } else if !plan.suggestions.isEmpty {
                        Image(systemName: "sparkles").font(.system(size: 8)).foregroundStyle(.purple).offset(x: 10, y: -10)
                    }
                }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(hasDeadline ? Color.red.opacity(0.85) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(plan.day == model.today ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 8).fill(plan.day == model.monthSelection ? Color.primary.opacity(0.12) : .clear))
        .opacity(inMonth ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.day.startDate(in: model.calendar).formatted(date: .complete, time: .omitted))
        .accessibilityValue(hasDeadline ? String(localized: "Deadline, \(CapacityText.summary(plan.capacity))") : CapacityText.summary(plan.capacity))
    }
}

/// Entries of the day picked in the month (mockup E1).
private struct MonthDayDetail: View {
    let model: PlanningModel
    let plan: DayPlan
    let onOpenDay: () -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onOpenTask: (TaskID) -> Void
    let deadlineActions: DeadlineActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.day.startDate(in: model.calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                Spacer()
                Text(CapacityText.summary(plan.capacity)).font(.caption).foregroundStyle(.secondaryText)
            }
            ForEach(plan.deadlines) { deadline in
                DeadlineLine(deadline: deadline)
                    .deadlineInteractions(deadline, model: model, actions: deadlineActions)
            }
            // All-day events of deadline calendars already appear as deadlines above.
            ForEach((model.allDayEvents(for: plan) + (plan.events + plan.blocks).filter { !$0.isAllDay })
                .sorted { $0.start < $1.start }) { event in
                Button { onOpenEvent(event) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.isAllDay ? String(localized: "ganztägig") : event.start.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondaryText).frame(width: 64, alignment: .leading)
                        Text(event.title).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(plan.assigned) { task in
                Button { onOpenTask(task.id) } label: { Label(task.title, systemImage: "circle").lineLimit(1) }
                    .buttonStyle(.plain)
            }
            ForEach(plan.suggestions) { suggestion in SuggestionRow(suggestion: suggestion) }
            if plan.events.isEmpty && plan.blocks.isEmpty && plan.assigned.isEmpty && plan.deadlines.isEmpty
                && plan.suggestions.isEmpty {
                Text("Nichts geplant").font(.subheadline).foregroundStyle(.secondaryText)
            }
            Button("Tag öffnen ›", action: onOpenDay).font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Picks an unplanned task for a day (month day menu).
private struct PlanTaskPicker: View {
    let model: PlanningModel
    let day: PlanDay
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            let sections = model.unplannedSections(search: search)
            List(sections.dueInRange + sections.other) { task in
                Button(task.title) {
                    Task { await model.assign(task.id, to: day) }
                    dismiss()
                }
                .foregroundStyle(.primary)
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $search, prompt: "Aufgabe suchen")
            .navigationTitle(day.startDate(in: model.calendar).formatted(.dateTime.weekday(.abbreviated).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}

extension PlanDay: @retroactive Identifiable {
    public var id: PlanDay { self }
}
