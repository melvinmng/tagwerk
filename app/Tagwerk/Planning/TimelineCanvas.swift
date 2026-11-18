import SwiftUI
import TagwerkCore

/// What the day shows at a time: a calendar event (a Tagwerk block when linked) or the lunch break.
enum DayEntry: Identifiable, Equatable {
    case event(CalendarEvent, TaskID?)
    case lunch(day: PlanDay, range: Range<Int>)

    var id: String {
        switch self {
        case .event(let event, _): event.id
        case .lunch: "lunch"
        }
    }
}

/// A finished change in the canvas, handed to the screen to write (and to ask for a series span first).
struct CanvasCommit: Equatable {
    let entry: DayEntry
    let range: Range<Int>
}

/// To-scale hour grid of one day (design §13.15 G1, S1, D1). Entries follow the finger without rounding;
/// only the target line and its time snap to 15 minutes, with a haptic tick per step. Writing happens once
/// on release; until the model has reloaded, the entry stays at its new place.
struct TimelineCanvas: View {
    let model: PlanningModel
    let plan: DayPlan
    let entries: [DayEntry]
    /// Selection mode for "Frei" (F1): taps toggle events instead of opening them.
    let selectingIDs: Set<String>?
    /// A task dragged from the "Ohne Uhrzeit" bar: its preview start in minutes and length.
    let taskPreview: (title: String, startMinutes: Int, minutes: Int)?
    let onTap: (DayEntry) -> Void
    let onToggleSelection: (CalendarEvent) -> Void
    let onCommit: (CanvasCommit) -> Void
    @Binding var isDragging: Bool

    static let hourHeight: CGFloat = 64
    static let lineInset: CGFloat = 8
    private let labelWidth: CGFloat = 44

    @Environment(AppEnvironment.self) private var environment
    @State private var openSuggestion: PlanSuggestion?
    @State private var selectedID: String?
    /// When the hold selected an entry; the release of that hold must not count as a tap.
    @State private var selectedAt = Date.distantPast
    @State private var session: Session?
    @State private var pending: [String: Range<Int>] = [:]

    private enum Mode { case move, start, end }

    private struct Session: Equatable {
        let id: String
        let mode: Mode
        let original: Range<Int>
        var delta: CGFloat
    }

    var body: some View {
        let shown = shownRange
        GeometryReader { geometry in
            let width = geometry.size.width - labelWidth - 6
            let ranges = entries.map(displayRange)
            let columns = TagwerkCore.columns(for: ranges)
            ZStack(alignment: .topLeading) {
                hourLines(shown)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }
                if let line = snapLine {
                    snapIndicator(minutes: line, shown: shown, width: geometry.size.width)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let range = liveRange(entry)
                    let count = columnCount(index: index, ranges: ranges, columns: columns)
                    let columnWidth = width / CGFloat(count)
                    entryView(entry, range: range)
                        .frame(width: columnWidth - 2, height: max(18, height(range.count)))
                        .offset(x: labelWidth + 6 + CGFloat(columns[index]) * columnWidth, y: y(range.lowerBound, shown))
                        .zIndex(session?.id == entry.id ? 2 : (selectedID == entry.id ? 1 : 0))
                }
                ForEach(blockSuggestions) { suggestion in
                    let range = Self.range(of: suggestion)
                    SuggestionBlock(suggestion: suggestion, timeText: timeText(range),
                                    onOpen: { openSuggestion = suggestion },
                                    onAccept: { Task { await environment.planner.accept(suggestion) } },
                                    onDismiss: { Task { await environment.planner.dismiss(suggestion) } })
                        .frame(width: width - 2, height: max(22, height(range.count)))
                        .offset(x: labelWidth + 6, y: y(range.lowerBound, shown))
                        .zIndex(0.5)
                }
                if let preview = taskPreview {
                    previewBlock(preview, shown: shown, width: width)
                }
            }
            .coordinateSpace(.named("canvas"))
        }
        .frame(height: height(shown.count) + Self.lineInset)
        .sensoryFeedback(.selection, trigger: snapLine)
        .sensoryFeedback(.impact(weight: .light), trigger: selectedID) { _, new in new != nil }
        .onChange(of: plan) { _, _ in pending.removeAll() }
        .sheet(item: $openSuggestion) { suggestion in SuggestionSheet(suggestion: suggestion) }
        .onChange(of: session != nil) { _, dragging in isDragging = dragging }
    }

    /// Visible hours: working time widened to every entry, with an hour of margin.
    var shownRange: Range<Int> {
        let hours = model.workHours(on: plan.day) ?? WorkHours(startMinutes: 540, endMinutes: 1080)
        let ranges = entries.map(baseRange) + blockSuggestions.map(Self.range)
        let lower = min(hours.startMinutes, ranges.map(\.lowerBound).min() ?? hours.startMinutes)
        let upper = max(hours.endMinutes, ranges.map(\.upperBound).max() ?? hours.endMinutes)
        return max(0, (lower / 60 - 1) * 60)..<min(1440, ((upper + 59) / 60 + 1) * 60)
    }

    /// Open AI time-block suggestions of the day (mockup W1).
    private var blockSuggestions: [PlanSuggestion] {
        plan.suggestions.filter { $0.kind == .block && $0.startMinutes != nil }
    }

    static func range(of suggestion: PlanSuggestion) -> Range<Int> {
        let start = suggestion.startMinutes ?? 0
        return start..<(start + max(15, suggestion.minutes ?? 15))
    }

    /// Minutes for a y position in the canvas (used for drops from the "Ohne Uhrzeit" bar).
    func minutes(atY y: CGFloat) -> Int {
        shownRange.lowerBound + Int((y - Self.lineInset) / Self.hourHeight * 60)
    }

    // MARK: Entries

    @ViewBuilder
    private func entryView(_ entry: DayEntry, range: Range<Int>) -> some View {
        let style = EntryStyle(entry: entry, model: model)
        let isSelected = selectedID == entry.id
        let isPicked = { if case .event(let event, _) = entry { selectingIDs?.contains(event.id) == true } else { false } }()
        ZStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isPicked { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    Text(style.title).font(.caption.weight(.semibold)).lineLimit(2)
                }
                Text(timeText(range) + style.suffix).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(style.color.opacity(style.isFree ? 0.08 : 0.24), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? style.color : (style.isFree ? Color.secondary : .clear),
                                  style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: style.isFree ? [4, 3] : []))
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(style.isFree ? Color.secondary : style.color).frame(width: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7))
            }
            .opacity(selectingIDs != nil && !style.isSelectable ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture { tap(entry) }
            .gesture(selectingIDs == nil && style.canMove ? moveGesture(entry) : nil)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(style.canMove ? "Halten, dann ziehen zum Verschieben" : "")

            if isSelected && style.canMove {
                VStack {
                    grip(entry, mode: .start, color: style.color, alignment: .trailing, label: "Beginn ändern")
                        .offset(y: -8)
                    Spacer()
                    grip(entry, mode: .end, color: style.color, alignment: .leading, label: "Ende ändern")
                        .offset(y: 8)
                }
            }
        }
    }

    private func tap(_ entry: DayEntry) {
        if selectingIDs != nil {
            if case .event(let event, _) = entry, EntryStyle(entry: entry, model: model).isSelectable { onToggleSelection(event) }
            return
        }
        if selectedID != nil, selectedID != entry.id { selectedID = nil; return }
        if selectedID == entry.id, Date.now.timeIntervalSince(selectedAt) < 0.8 { return }
        onTap(entry)
    }

    /// Hold 0.3 s to select (grips appear); keep holding and move to drag.
    private func moveGesture(_ entry: DayEntry) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas")))
            .onChanged { value in
                switch value {
                case .second(true, nil):
                    if selectedID != entry.id { selectedAt = .now }
                    selectedID = entry.id
                case .second(true, let drag?):
                    selectedID = entry.id
                    if session == nil {
                        session = Session(id: entry.id, mode: .move, original: displayRange(entry), delta: 0)
                    }
                    session?.delta = drag.translation.height
                default: break
                }
            }
            .onEnded { _ in finishSession(entry) }
    }

    private func grip(_ entry: DayEntry, mode: Mode, color: Color, alignment: Alignment, label: String) -> some View {
        Circle().fill(color).stroke(.background, lineWidth: 2).frame(width: 14, height: 14)
            .padding(7)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: alignment)
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                .onChanged { drag in
                    if session == nil { session = Session(id: entry.id, mode: mode, original: displayRange(entry), delta: 0) }
                    session?.delta = drag.translation.height
                }
                .onEnded { _ in finishSession(entry) })
            .accessibilityLabel(label)
    }

    private func finishSession(_ entry: DayEntry) {
        guard let current = session, current.id == entry.id else { return }
        let target = snappedRange(current)
        session = nil
        guard target != current.original else { return }
        withAnimation(.snappy(duration: 0.2)) { pending[entry.id] = target }
        onCommit(CanvasCommit(entry: entry, range: target))
    }

    // MARK: Geometry

    private func baseRange(_ entry: DayEntry) -> Range<Int> {
        switch entry {
        case .lunch(_, let range): return range
        case .event(let event, _):
            let dayStart = plan.day.startDate(in: model.calendar)
            let start = max(0, Int(event.start.timeIntervalSince(dayStart) / 60))
            return start..<max(start + 15, min(1440, Int(event.end.timeIntervalSince(dayStart) / 60)))
        }
    }

    private func displayRange(_ entry: DayEntry) -> Range<Int> {
        pending[entry.id] ?? baseRange(entry)
    }

    /// Unrounded position while dragging (follows the finger), else the stored range.
    private func liveRange(_ entry: DayEntry) -> Range<Int> {
        guard let session, session.id == entry.id else { return displayRange(entry) }
        let delta = Int((session.delta / Self.hourHeight * 60).rounded())
        return apply(delta, to: session)
    }

    private func apply(_ delta: Int, to session: Session) -> Range<Int> {
        let original = session.original
        switch session.mode {
        case .move:
            let start = min(max(0, original.lowerBound + delta), 1440 - original.count)
            return start..<(start + original.count)
        case .start:
            let start = min(max(0, original.lowerBound + delta), original.upperBound - 15)
            return start..<original.upperBound
        case .end:
            let end = max(min(1440, original.upperBound + delta), original.lowerBound + 15)
            return original.lowerBound..<end
        }
    }

    private func snappedRange(_ session: Session) -> Range<Int> {
        let delta = snapped(minutes: Int((session.delta / Self.hourHeight * 60).rounded()))
        return apply(delta, to: session)
    }

    /// Start (or end for the end grip) the dragged entry will snap to.
    private var snapLine: Int? {
        guard let session else { return nil }
        let range = snappedRange(session)
        return session.mode == .end ? range.upperBound : range.lowerBound
    }

    private func snapIndicator(minutes: Int, shown: Range<Int>, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(clock(minutes)).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(.red)
                .frame(width: labelWidth, alignment: .leading)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .frame(width: width)
        .offset(y: y(minutes, shown) - 7)
        .allowsHitTesting(false)
    }

    private func previewBlock(_ preview: (title: String, startMinutes: Int, minutes: Int), shown: Range<Int>, width: CGFloat) -> some View {
        let start = snapped(minutes: preview.startMinutes)
        return ZStack(alignment: .topLeading) {
            snapIndicator(minutes: start, shown: shown, width: width + labelWidth + 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(preview.title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(timeText(start..<(start + preview.minutes))).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(width: width - 2, height: max(18, height(preview.minutes)), alignment: .topLeading)
            .background(Color.green.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.green, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
            .offset(x: labelWidth + 6, y: y(start, shown))
        }
        .allowsHitTesting(false)
    }

    private func columnCount(index: Int, ranges: [Range<Int>], columns: [Int]) -> Int {
        let overlapping = ranges.indices.filter { ranges[$0].overlaps(ranges[index]) }
        return (overlapping.map { columns[$0] }.max() ?? 0) + 1
    }

    private func hourLines(_ shown: Range<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: shown.lowerBound, to: shown.upperBound, by: 60)), id: \.self) { minutes in
                HStack(alignment: .top, spacing: 6) {
                    Text(String(format: "%02d:00", minutes / 60))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                    Rectangle().fill(.quaternary).frame(height: 0.5).padding(.top, Self.lineInset)
                }
                .frame(height: Self.hourHeight, alignment: .top)
            }
        }
    }

    private func y(_ minutes: Int, _ shown: Range<Int>) -> CGFloat {
        CGFloat(minutes - shown.lowerBound) / 60 * Self.hourHeight + Self.lineInset
    }

    private func height(_ minutes: Int) -> CGFloat {
        CGFloat(minutes) / 60 * Self.hourHeight
    }

    private func clock(_ minutes: Int) -> String {
        plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private func timeText(_ range: Range<Int>) -> String {
        "\(clock(range.lowerBound))–\(clock(range.upperBound))"
    }
}

/// Colour, wording and allowed interactions of an entry.
struct EntryStyle {
    let title: String
    let color: Color
    let isFree: Bool
    let canMove: Bool
    /// Can take part in "Frei" selection (calendar events, not blocks or the break).
    let isSelectable: Bool
    let suffix: String

    @MainActor
    init(entry: DayEntry, model: PlanningModel) {
        switch entry {
        case .lunch:
            title = "Mittagspause"; color = .gray; isFree = false; canMove = true; isSelectable = false; suffix = ""
        case .event(let event, let taskID):
            title = event.title
            isFree = !event.isBusy
            canMove = model.canDrag(event)
            let isBlock = taskID != nil && model.canEditAsBlock(event)
            isSelectable = !isBlock
            color = isBlock ? .green : (taskID != nil ? .teal : .blue)
            var parts: [String] = []
            if isFree { parts.append("Frei") }
            if !event.isEditable { parts.append("🔒") } else if event.isInvitation { parts.append("Einladung") }
            if event.isRecurring { parts.append("↻") }
            if !event.mergedCalendarIDs.isEmpty { parts.append("\(event.mergedCalendarIDs.count + 1) Kalender") }
            suffix = parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
        }
    }
}
