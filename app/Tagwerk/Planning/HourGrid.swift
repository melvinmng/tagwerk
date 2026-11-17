import SwiftUI
import TagwerkCore

/// To-scale hour grid of a day (mockup C3): events and blocks side by side when they overlap; blocks move by
/// dragging their body and change length with the handle at the bottom (15-minute steps). Tasks dropped on
/// the grid become blocks at that time.
struct HourGrid: View {
    let model: PlanningModel
    let plan: DayPlan
    let onOpenEvent: (CalendarEvent) -> Void
    let blockMenu: (CalendarEvent, TaskID) -> BlockMenu

    static let hourHeight: CGFloat = 60
    static let lineInset: CGFloat = 6
    private let labelWidth: CGFloat = 44

    private struct Item: Identifiable {
        let id: String
        let range: Range<Int>
        let title: String
        let event: CalendarEvent?
        let taskID: TaskID?
    }

    var body: some View {
        let items = self.items
        let columns = TagwerkCore.columns(for: items.map(\.range))
        let shown = visibleRange(items)
        GeometryReader { geometry in
            let width = geometry.size.width - labelWidth - 4
            ZStack(alignment: .topLeading) {
                hourLines(shown)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let count = columnCount(for: item, items: items, columns: columns)
                    let columnWidth = width / CGFloat(count)
                    GridEntry(title: item.title, range: item.range, isBlock: item.taskID != nil,
                              model: model, plan: plan, event: item.event,
                              onOpenEvent: onOpenEvent, menu: item.event.flatMap { event in item.taskID.map { blockMenu(event, $0) } })
                        .frame(width: columnWidth - 2, height: height(item.range.count))
                        .offset(x: labelWidth + 4 + CGFloat(columns[index]) * columnWidth, y: y(item.range.lowerBound, shown))
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { keys, location in
                guard let key = keys.first else { return false }
                let minutes = shown.lowerBound + Int((location.y - Self.lineInset) / Self.hourHeight * 60)
                Task { await model.dropTask(key: key, atMinutes: minutes, on: plan.day) }
                return true
            }
        }
        .frame(height: height(shown.count))
    }

    private var items: [Item] {
        let dayStart = plan.day.startDate(in: model.calendar)
        func range(_ event: CalendarEvent) -> Range<Int> {
            let start = max(0, Int(event.start.timeIntervalSince(dayStart) / 60))
            return start..<max(start + 15, min(1440, Int(event.end.timeIntervalSince(dayStart) / 60)))
        }
        var result: [Item] = plan.events.filter { !$0.isAllDay }.map {
            Item(id: $0.id, range: range($0), title: $0.title, event: $0, taskID: nil)
        }
        result += plan.blocks.compactMap { block in
            plan.links[block.id].map { Item(id: block.id, range: range(block), title: block.title, event: block, taskID: $0) }
        }
        if let lunch = model.timeline(for: plan).first(where: { if case .lunch = $0 { true } else { false } }),
           case .lunch(let start, let minutes) = lunch {
            result.append(Item(id: "lunch", range: start..<(start + minutes), title: "Mittagspause", event: nil, taskID: nil))
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Working hours widened to every entry, rounded to full hours, with an hour of margin.
    private func visibleRange(_ items: [Item]) -> Range<Int> {
        let hours = model.workHours(on: plan.day) ?? WorkHours(startMinutes: 540, endMinutes: 1080)
        let lower = min(hours.startMinutes, items.map(\.range.lowerBound).min() ?? hours.startMinutes)
        let upper = max(hours.endMinutes, items.map(\.range.upperBound).max() ?? hours.endMinutes)
        return max(0, (lower / 60 - 1) * 60)..<min(1440, (upper / 60 + 1) * 60 + (upper % 60 == 0 ? 0 : 60))
    }

    private func columnCount(for item: Item, items: [Item], columns: [Int]) -> Int {
        let overlapping = items.indices.filter { items[$0].range.overlaps(item.range) }
        return (overlapping.map { columns[$0] }.max() ?? 0) + 1
    }

    private func hourLines(_ shown: Range<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: shown.lowerBound, to: shown.upperBound, by: 60)), id: \.self) { minutes in
                HStack(alignment: .top, spacing: 4) {
                    Text(String(format: "%02d:00", minutes / 60))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                    Rectangle().fill(.quaternary).frame(height: 0.5).padding(.top, Self.lineInset)
                }
                .frame(height: Self.hourHeight, alignment: .top)
            }
        }
    }

    /// Hour lines sit `lineInset` below the top of their row (aligned with the label), entries follow them.
    private func y(_ minutes: Int, _ shown: Range<Int>) -> CGFloat {
        CGFloat(minutes - shown.lowerBound) / 60 * Self.hourHeight + Self.lineInset
    }

    private func height(_ minutes: Int) -> CGFloat {
        CGFloat(minutes) / 60 * Self.hourHeight
    }
}

/// One entry of the grid; blocks can be dragged (after a short hold) and resized with the bottom handle.
private struct GridEntry: View {
    let title: String
    let range: Range<Int>
    let isBlock: Bool
    let model: PlanningModel
    let plan: DayPlan
    let event: CalendarEvent?
    let onOpenEvent: (CalendarEvent) -> Void
    let menu: BlockMenu?
    @State private var moveOffset: CGFloat = 0
    @State private var resizeOffset: CGFloat = 0

    var body: some View {
        let color: Color = isBlock ? .green : (event == nil ? .gray : .blue)
        ZStack(alignment: .bottom) {
            content(color)
            if isBlock, let event {
                Capsule().fill(color).frame(width: 28, height: 5).padding(.bottom, 3)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .bottom)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { resizeOffset = $0.translation.height }
                        .onEnded { value in
                            let delta = Int(value.translation.height / HourGrid.hourHeight * 60)
                            resizeOffset = 0
                            Task { await model.resizeBlock(event, minutes: range.count + delta) }
                        })
                    .accessibilityLabel("Dauer ändern")
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, -resizeOffset)
        .offset(y: moveOffset)
        .simultaneousGesture(isBlock ? moveGesture : nil)
    }

    @ViewBuilder
    private func content(_ color: Color) -> some View {
        let label = VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold)).lineLimit(2)
            Text(timeText).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))

        if let menu {
            Menu { menu } label: { label }.buttonStyle(.plain)
        } else if let event {
            Button { onOpenEvent(event) } label: { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Dragging a block moves it; it starts after a few points, so a tap still opens the menu.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { moveOffset = $0.translation.height }
            .onEnded { value in
                guard let event else { moveOffset = 0; return }
                let delta = Int(value.translation.height / HourGrid.hourHeight * 60)
                moveOffset = 0
                Task { await model.moveBlock(event, toStartMinutes: range.lowerBound + delta, on: plan.day) }
            }
    }

    private var timeText: String {
        let start = plan.day.startDate(in: model.calendar)
        func clock(_ minutes: Int) -> String {
            start.addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
        }
        return "\(clock(range.lowerBound))–\(clock(range.upperBound))"
    }
}

/// Menu of a time block (mockup C1): ±15 min for start and length, another day, show task, delete.
struct BlockMenu: View {
    let block: CalendarEvent
    let taskID: TaskID
    let model: PlanningModel
    let onShowTask: (TaskID) -> Void
    let onMoveToDay: (CalendarEvent) -> Void

    var body: some View {
        let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
        let day = PlanDay(date: block.start, calendar: model.calendar)
        let start = Int(block.start.timeIntervalSince(day.startDate(in: model.calendar)) / 60)
        Section("Beginn \(block.start.formatted(date: .omitted, time: .shortened))") {
            ControlGroup {
                Button("15 min früher", systemImage: "arrow.up") {
                    Task { await model.moveBlock(block, toStartMinutes: start - 15, on: day) }
                }
                Button("15 min später", systemImage: "arrow.down") {
                    Task { await model.moveBlock(block, toStartMinutes: start + 15, on: day) }
                }
            }
        }
        Section("Dauer \(CapacityText.duration(minutes))") {
            ControlGroup {
                Button("15 min kürzer", systemImage: "minus") { Task { await model.resizeBlock(block, minutes: minutes - 15) } }
                    .disabled(minutes <= 15)
                Button("15 min länger", systemImage: "plus") { Task { await model.resizeBlock(block, minutes: minutes + 15) } }
            }
        }
        Button("Auf anderen Tag …", systemImage: "calendar") { onMoveToDay(block) }
        Button("Aufgabe zeigen", systemImage: "checklist") { onShowTask(taskID) }
        Button("Zeitblock löschen", systemImage: "trash", role: .destructive) { Task { await model.deleteBlock(block) } }
    }
}

/// Picks another day for a block; time of day and length stay.
struct BlockDaySheet: View {
    let block: CalendarEvent
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(block: CalendarEvent, model: PlanningModel) {
        self.block = block
        self.model = model
        _date = State(initialValue: block.start)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Tag", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, model.calendar)
                .padding()
                .navigationTitle("Auf anderen Tag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verschieben") {
                            let oldDay = PlanDay(date: block.start, calendar: model.calendar)
                            let start = Int(block.start.timeIntervalSince(oldDay.startDate(in: model.calendar)) / 60)
                            Task { await model.moveBlock(block, toStartMinutes: start, on: PlanDay(date: date, calendar: model.calendar)) }
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
