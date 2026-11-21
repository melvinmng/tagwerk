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
    /// Width of the hour label column; grows with the text size (capped), so "08:00" is not squeezed at large sizes.
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelWidth: CGFloat = 44
    private var labelWidth: CGFloat { min(scaledLabelWidth, 76) }

    /// Narrowest a column of overlapping entries may get before the group becomes one block (about six characters of
    /// the title font; grows with the text size, BF1c).
    @ScaledMetric(relativeTo: .caption) private var minimumColumnWidth: CGFloat = 44

    @Environment(AppEnvironment.self) private var environment
    /// Set in the preview of a neighbour page: the marks of its events.
    @Environment(\.dayPageExtras) private var pageExtras
    @State private var openSuggestion: PlanSuggestion?
    @State private var editingTask: TaskItem?
    @State private var selectedID: String?
    /// When the hold selected an entry; the release of that hold must not count as a tap.
    @State private var selectedAt = Date.distantPast
    @State private var session: Session?
    /// The hold-and-drag on an entry (UIKit recognizer, SR1 path B).
    @State private var hold = HoldMoveState()
    @State private var pending: [String: Range<Int>] = [:]
    /// The collapsed group whose list is open.
    @State private var openGroup: CollapsedGroup?

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
            // Overlapping entries whose columns would be too narrow become one block each (BF1c); never while choosing "Frei".
            let groups = collapsedGroups(ranges: ranges, columns: columns, width: width)
            let collapsed = Set(groups.flatMap { $0 })
            ZStack(alignment: .topLeading) {
                hourLines(shown)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }
                if let line = snapLine {
                    snapIndicator(minutes: line, shown: shown, width: geometry.size.width)
                }
                // Travel time lies behind the entries, in the column of the event it leads to (#168).
                ForEach(plan.travel) { segment in
                    if let index = entries.firstIndex(where: { $0.id == segment.eventID }) {
                        // Behind a collapsed group the travel time takes the full width.
                        let isCollapsed = collapsed.contains(index)
                        let columnWidth = isCollapsed ? width : width / CGFloat(columnCount(index: index, ranges: ranges, columns: columns))
                        TravelSegmentView(segment: segment, transport: model.settings.travelTransport)
                            .frame(width: columnWidth - 2, height: max(14, height(segment.range.count)))
                            .offset(x: labelWidth + 6 + CGFloat(isCollapsed ? 0 : columns[index]) * columnWidth, y: y(segment.range.lowerBound, shown))
                            .allowsHitTesting(false)
                    }
                }
                ForEach(groups, id: \.self) { group in
                    collapsedBlock(group, ranges: ranges, shown: shown, width: width)
                }
                ForEach(Array(entries.enumerated()).filter { !collapsed.contains($0.offset) }, id: \.element.id) { index, entry in
                    let range = liveRange(entry)
                    let count = columnCount(index: index, ranges: ranges, columns: columns)
                    let columnWidth = width / CGFloat(count)
                    entryView(entry, range: range)
                        .frame(width: columnWidth - 2, height: max(18, height(range.count)))
                        .offset(x: labelWidth + 6 + CGFloat(columns[index]) * columnWidth, y: y(range.lowerBound, shown))
                        .zIndex(session?.id == entry.id ? 2 : (selectedID == entry.id ? 1 : 0))
                }
                // Mockup AR1: the added time of a suggested longer day, hatched purple.
                ForEach(extensionRanges, id: \.lowerBound) { range in
                    Rectangle()
                        .fill(Color.purple.opacity(0.10))
                        .overlay { Rectangle().strokeBorder(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                        .frame(width: width, height: height(range.count))
                        .offset(x: labelWidth + 6, y: y(range.lowerBound, shown))
                        .allowsHitTesting(false)
                }
                // Mockup VA1: where a changed suggestion was, faded, until the next change.
                ForEach(changedFrom, id: \.id) { suggestion in
                    if let start = suggestion.previousPosition?.startMinutes, let minutes = suggestion.previousPosition?.minutes {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.purple.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            .frame(width: width - 2, height: max(22, height(minutes)))
                            .offset(x: labelWidth + 6, y: y(start, shown))
                            .allowsHitTesting(false)
                    }
                }
                ForEach(blockSuggestions) { suggestion in
                    let range = Self.range(of: suggestion)
                    SuggestionBlock(suggestion: suggestion, timeText: timeText(range),
                                    acceptEnabled: !SuggestionText.isWaiting(suggestion, planning: model),
                                    onOpen: { if !environment.voiceMode.isRunning { openSuggestion = suggestion } },
                                    onAccept: { Task { await environment.planner.accept(suggestion) } },
                                    onDismiss: { Task { await environment.planner.dismiss(suggestion) } },
                                    onOpenTask: model.taskList.items.first { $0.id.key == suggestion.taskKey }.map { task in
                                        { editingTask = task }
                                    })
                        .frame(width: width - 2, height: max(22, height(range.count)))
                        .offset(x: labelWidth + 6, y: y(range.lowerBound, shown))
                        .zIndex(0.5)
                }
                if let preview = taskPreview {
                    previewBlock(preview, shown: shown, width: width)
                }
                NowLine(model: model, day: plan.day, shown: shown, labelWidth: labelWidth, width: geometry.size.width)
                    .zIndex(3)
            }
            .coordinateSpace(.named("canvas"))
        }
        .frame(height: height(shown.count) + Self.lineInset)
        .sensoryFeedback(.selection, trigger: snapLine)
        .sensoryFeedback(.impact(weight: .light), trigger: selectedID) { _, new in new != nil }
        .onChange(of: plan) { _, _ in pending.removeAll() }
        .sheet(item: $openGroup) { group in
            CollapsedGroupList(rows: group.rows) { entry in
                // No sheet over a sheet: the list closes first, the entry opens afterwards.
                openGroup = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    onTap(entry)
                }
            }
        }
        .sheet(item: $openSuggestion) { suggestion in SuggestionSheet(suggestion: suggestion) }
        .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
        // Scrolling stops as soon as an entry is held, not only once it moves (SR1).
        .onChange(of: hold.blocksScroll || session != nil) { _, dragging in isDragging = dragging }
    }

    /// Visible hours: working time widened to every entry, with an hour of margin.
    var shownRange: Range<Int> {
        let hours = model.workHours(on: plan.day) ?? WorkHours(startMinutes: 540, endMinutes: 1080)
        let ranges = entries.map(baseRange) + blockSuggestions.map(Self.range) + extensionRanges + plan.travel.map(\.range)
        let lower = min(hours.startMinutes, ranges.map(\.lowerBound).min() ?? hours.startMinutes)
        let upper = max(hours.endMinutes, ranges.map(\.upperBound).max() ?? hours.endMinutes)
        return max(0, (lower / 60 - 1) * 60)..<min(1440, ((upper + 59) / 60 + 1) * 60)
    }

    /// Open AI time-block suggestions of the day (mockup W1).
    private var blockSuggestions: [PlanSuggestion] {
        plan.suggestions.filter { $0.kind == .block && $0.startMinutes != nil }
    }

    /// Suggestions an answer moved within this day: their old place is drawn faded.
    private var changedFrom: [PlanSuggestion] {
        blockSuggestions.filter { $0.previousPosition?.kind == .block && $0.previousPosition?.day == plan.day
            && $0.previousPosition?.startMinutes != $0.startMinutes }
    }

    /// Time a pending longer day would add, outside today's working hours.
    private var extensionRanges: [Range<Int>] {
        guard let change = plan.suggestions.first(where: { $0.kind == .dayChange }),
              let start = change.startMinutes, let end = change.endMinutes else { return [] }
        guard let hours = model.workHours(on: plan.day), hours.minutes > 0 else { return [start..<end] }
        var ranges: [Range<Int>] = []
        if start < hours.startMinutes { ranges.append(start..<hours.startMinutes) }
        if end > hours.endMinutes { ranges.append(hours.endMinutes..<end) }
        return ranges
    }

    static func range(of suggestion: PlanSuggestion) -> Range<Int> {
        let start = suggestion.startMinutes ?? 0
        return start..<(start + max(15, suggestion.minutes ?? 15))
    }

    /// Minutes for a y position in the canvas (used for drops from the "Ohne Uhrzeit" bar).
    func minutes(atY y: CGFloat) -> Int {
        shownRange.lowerBound + Int((y - Self.lineInset) / Self.hourHeight * 60)
    }

    // MARK: Collapsed groups (BF1c)

    /// The groups of entries (indices) that become one block: they overlap, need more than one column and a column would be
    /// narrower than `minimumColumnWidth`. A group is never made of one entry.
    private func collapsedGroups(ranges: [Range<Int>], columns: [Int], width: CGFloat) -> [[Int]] {
        guard selectingIDs == nil else { return [] }
        return TagwerkCore.overlapGroups(for: ranges).filter { group in
            let columnCount = group.map { columnCount(index: $0, ranges: ranges, columns: columns) }.max() ?? 1
            return group.count > 1 && GridCollapse.collapses(columnCount: columnCount, availableWidth: Double(width),
                                                            minimumColumnWidth: Double(minimumColumnWidth))
        }
    }

    /// The block of one collapsed group over its whole time span; its running state follows the minute.
    private func collapsedBlock(_ group: [Int], ranges: [Range<Int>], shown: Range<Int>, width: CGFloat) -> some View {
        let members = group.map { entries[$0] }
        let span = (group.map { ranges[$0].lowerBound }.min() ?? 0)..<(group.map { ranges[$0].upperBound }.max() ?? 0)
        let marks = pageExtras ?? model.currentExtras
        let styles = members.map { EntryStyle(entry: $0, model: model, extras: pageExtras) }
        let hasDeadline = members.contains { member in
            if case .event(let event, _) = member { return marks.deadlineEventIDs.contains(event.id) }
            return false
        }
        let rows = zip(members, group).map { member, index in
            let style = EntryStyle(entry: member, model: model, extras: pageExtras)
            return CollapsedGroupRow(entry: member, time: timeText(ranges[index]), title: style.title, suffix: style.suffix,
                                     color: style.isFree ? .secondary : style.color)
        }
        return TimelineView(.everyMinute) { _ in
            CollapsedGroupBlock(count: members.count, timeText: timeText(span), startText: clock(span.lowerBound),
                                endText: clock(span.upperBound), titles: styles.map(\.title), hasDeadline: hasDeadline,
                                isRunning: members.contains { runningRemaining($0) != nil },
                                height: max(18, height(span.count))) {
                openGroup = CollapsedGroup(rows: rows)
            }
        }
        .frame(width: width - 2, height: max(18, height(span.count)))
        .offset(x: labelWidth + 6, y: y(span.lowerBound, shown))
    }

    // MARK: Entries

    /// An entry; the content is rebuilt every full minute, so a running entry changes its state on time (PL2b).
    private func entryView(_ entry: DayEntry, range: Range<Int>) -> some View {
        TimelineView(.everyMinute) { _ in entryContent(entry, range: range) }
    }

    /// Minutes left when the entry is running now (a break and calendar events, also time blocks; never all-day).
    private func runningRemaining(_ entry: DayEntry) -> Int? {
        switch entry {
        case .lunch(_, let range): model.runningRemaining(range: range, on: plan.day)
        case .event(let event, _): model.runningRemaining(of: event, on: plan.day)
        }
    }

    @ViewBuilder
    private func entryContent(_ entry: DayEntry, range: Range<Int>) -> some View {
        let style = EntryStyle(entry: entry, model: model, extras: pageExtras)
        let isSelected = selectedID == entry.id
        let remaining = runningRemaining(entry)
        let isPicked = { if case .event(let event, _) = entry { selectingIDs?.contains(event.id) == true } else { false } }()
        ZStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isPicked { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    Text(style.title).font(.caption.weight(.semibold)).lineLimit(2)
                }
                Text((remaining.map { NowText.runningDetail(remainingMinutes: $0) } ?? timeText(range)) + style.suffix)
                    .font(.caption2).foregroundStyle(.secondaryText).lineLimit(1)
                    .accessibilityLabel((remaining.map { NowText.runningAccessibility(remainingMinutes: $0) } ?? timeText(range))
                        + style.suffix)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(style.color.opacity(style.isFree ? 0.08 : 0.24), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    // The selection keeps priority; a running entry has the same 2-pt frame in its colour (PL2b).
                    .strokeBorder(isSelected || remaining != nil ? style.color : (style.isFree ? Color.secondary : .clear),
                                  style: StrokeStyle(lineWidth: isSelected || remaining != nil ? 2 : 1,
                                                     dash: style.isFree && !isSelected && remaining == nil ? [4, 3] : []))
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(style.isFree ? Color.secondary : style.color).frame(width: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7))
            }
            .opacity(selectingIDs != nil && !style.isSelectable ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture { tap(entry) }
            .gesture(HoldToMoveRecognizer(isEnabled: selectingIDs == nil && style.canMove) { handleHold($0, entry: entry) })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(style.canMove ? "Halten, dann ziehen zum Verschieben" : "")

            if isSelected && style.canMove {
                VStack {
                    grip(entry, mode: .start, color: style.color, alignment: .trailing, label: String(localized: "Beginn ändern"))
                        .offset(y: -8)
                    Spacer()
                    grip(entry, mode: .end, color: style.color, alignment: .leading, label: String(localized: "Ende ändern"))
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

    /// Hold 0.3 s to select (grips appear) and block scrolling; keep holding and move to drag (SR1, path B).
    private func handleHold(_ event: HoldToMoveRecognizer.Event, entry: DayEntry) {
        switch event {
        case .began(let y):
            hold.begin(atY: y)
            // The release of this hold must not count as a tap.
            if selectedID != entry.id { selectedAt = .now }
            selectedID = entry.id
        case .changed(let y):
            hold.move(toY: y)
            if session == nil {
                session = Session(id: entry.id, mode: .move, original: displayRange(entry), delta: 0)
            }
            session?.delta = hold.delta
        case .ended:
            hold.end()
            finishSession(entry)
        case .cancelled:
            hold.end()
            if session?.id == entry.id { session = nil }
        }
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
        HStack(spacing: NowTimeCapsule.lineSpacing) {
            // Same capsule as the "now" marker, so the time keeps its contrast on the dark grid as well.
            NowTimeCapsule(time: clock(minutes), width: labelWidth + NowTimeCapsule.columnOverhang)
            Rectangle().fill(.nowMarkerFill).frame(height: 1.5)
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
                Text(timeText(start..<(start + preview.minutes))).font(.caption2).foregroundStyle(.secondaryText)
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
                    Text(DateText.time(minutes: minutes / 60 * 60, calendar: model.calendar))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: labelWidth, alignment: .leading)
                    Rectangle().fill(.quaternary).frame(height: 0.5).padding(.top, Self.lineInset)
                }
                .frame(height: Self.hourHeight, alignment: .top)
            }
        }
    }

    private func y(_ minutes: Int, _ shown: Range<Int>) -> CGFloat {
        Self.y(minutes, shown)
    }

    /// Vertical position of a time in the canvas; also used by the "now" line.
    static func y(_ minutes: Int, _ shown: Range<Int>) -> CGFloat {
        CGFloat(minutes - shown.lowerBound) / 60 * hourHeight + lineInset
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
    init(entry: DayEntry, model: PlanningModel, extras: DayPageExtras? = nil) {
        let marks = extras ?? model.currentExtras
        switch entry {
        case .lunch:
            title = String(localized: "Mittagspause"); color = .gray; isFree = false; canMove = true; isSelectable = false; suffix = ""
        case .event(let event, let taskID):
            var title = event.title
            isFree = !event.isBusy
            canMove = model.canDrag(event)
            let isBlock = taskID != nil && model.canEditAsBlock(event)
            isSelectable = !isBlock
            // Deadline events (deadline calendars and marked) are red in the timeline, with a text mark (DL2).
            let isDeadline = marks.deadlineEventIDs.contains(event.id)
            if isDeadline { title = "⚑ " + event.title }
            // The time block of today's focus task carries the star as well (phase 7).
            if let taskID, model.focusTaskIDs.contains(taskID), PlanDay(date: event.start, calendar: model.calendar) == model.today {
                title = "★ " + title
            }
            color = isDeadline ? .red : (isBlock ? .green : (taskID != nil ? .teal : .blue))
            var parts: [String] = []
            let text = DeadlineText(calendar: model.calendar)
            if isDeadline { parts.append(text.timelineMark(isMarked: !model.isInDeadlineCalendar(event))) }
            if let target = marks.preparationTargets[event.id] { parts.append(text.preparationMark(target, today: model.today)) }
            if isFree { parts.append(String(localized: "Frei")) }
            if !event.isEditable { parts.append("🔒") } else if event.isInvitation { parts.append(String(localized: "Einladung")) }
            if event.isRecurring { parts.append("↻") }
            if !event.mergedCalendarIDs.isEmpty { parts.append(String(localized: "\(event.mergedCalendarIDs.count + 1) Kalender")) }
            suffix = parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
            self.title = title
        }
    }
}
