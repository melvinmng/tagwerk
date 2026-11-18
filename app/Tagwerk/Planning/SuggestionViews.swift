import SwiftUI
import TagwerkCore

// MARK: Capsules (mockups VC1, VU1)

extension SuggestionFacts.Urgency {
    var color: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .none: .secondary
        }
    }
}

/// "P1" next to the title: red for P1, orange for P2, neutral otherwise.
struct PriorityMark: View {
    let mark: SuggestionFacts.Mark

    var body: some View {
        Text(mark.text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(mark.urgency == .none ? Color.secondary : Color.white)
            .background(mark.urgency == .none ? Color.secondary.opacity(0.2) : mark.urgency.color, in: Capsule())
            .fixedSize()
    }
}

/// One capsule of a suggestion: due date, effort or move target. Only capsules carry colour (mockup VU1).
struct FactCapsule: View {
    let text: String
    var symbol: String?
    var urgency: SuggestionFacts.Urgency = .none
    var tint: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(urgency == .high ? .semibold : .regular))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint ?? (urgency == .none ? Color.primary.opacity(0.75) : urgency.color))
        .background((tint ?? (urgency == .none ? Color.secondary : urgency.color)).opacity(0.15), in: Capsule())
        .fixedSize()
    }
}

/// Due date, effort and (for moves) the target as capsules; shortens itself when the width is short
/// (mockup VC1: "⚑ 20.11." and "von 3 h", then no effort, then only an urgent due date).
struct SuggestionCapsules: View {
    let facts: SuggestionFacts

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(due: facts.due?.text, effort: facts.effort)
            row(due: facts.dueShort, effort: facts.effortShort ?? facts.effort)
            row(due: facts.dueShort, effort: nil)
            row(due: facts.dueIsUrgent ? facts.dueShort : nil, effort: nil, withMove: false)
            EmptyView()
        }
    }

    private func row(due: String?, effort: String?, withMove: Bool = true) -> some View {
        HStack(spacing: 4) {
            if withMove, let target = facts.moveTarget {
                FactCapsule(text: target.text, symbol: "arrow.uturn.right", urgency: target.urgency,
                            tint: target.urgency == .none ? .purple : nil)
            }
            if let due { FactCapsule(text: due, symbol: "flag.fill", urgency: facts.due?.urgency ?? .none) }
            if let effort { FactCapsule(text: effort) }
        }
    }
}

// MARK: Grid block (mockup VC1)

/// An AI suggestion in the hour grid: purple, dashed, with priority, due date and effort instead of time
/// and buttons. A tap opens the suggestion sheet, holding shows a menu (mockup VT1).
struct SuggestionBlock: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    let timeText: String
    var acceptEnabled = true
    let onOpen: () -> Void
    let onAccept: () -> Void
    let onDismiss: () -> Void
    var onOpenTask: (() -> Void)?

    var body: some View {
        let facts = environment.planning.facts(for: suggestion)
        // The block's height is its duration; what does not fit is left out in a fixed order.
        ViewThatFits(in: .vertical) {
            content(facts, time: true, reasonLines: 2)
            content(facts, time: true, reasonLines: 0)
            content(facts, time: false, reasonLines: 0)
            singleLine(facts)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        // Changed by an answer: solid outline (mockup VA1); otherwise dashed like every suggestion.
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.purple, style: StrokeStyle(lineWidth: suggestion.previousPosition == nil ? 1 : 1.5,
                                                               dash: suggestion.previousPosition == nil ? [4, 3] : []))
        }
        .foregroundStyle(.purple)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            SuggestionMenu(acceptEnabled: acceptEnabled, onAccept: onAccept, onOpenTask: onOpenTask, onDismiss: onDismiss)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SuggestionText.accessibility(suggestion, facts: facts, time: timeText))
        .accessibilityAction(named: "Übernehmen", onAccept)
        .accessibilityAction(named: "Verwerfen", onDismiss)
    }

    private func content(_ facts: SuggestionFacts, time: Bool, reasonLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLine(facts)
            SuggestionCapsules(facts: facts)
            if time { Text(timeText).font(.caption2).foregroundStyle(.secondary) }
            if reasonLines > 0, !suggestion.reason.isEmpty {
                Text("„\(suggestion.reason)“").font(.caption2).lineLimit(reasonLines)
            }
        }
    }

    /// 15-minute blocks: ✦ title, an urgent due date, P mark.
    private func singleLine(_ facts: SuggestionFacts) -> some View {
        HStack(spacing: 4) {
            Image(systemName: suggestion.isMovedByUser ? "pencil" : "sparkles").font(.caption2)
            Text(suggestion.title).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if facts.dueIsUrgent, let due = facts.dueShort {
                FactCapsule(text: due, symbol: "flag.fill", urgency: facts.due?.urgency ?? .none)
            }
            if let priority = facts.priority { PriorityMark(mark: priority) }
        }
    }

    private func titleLine(_ facts: SuggestionFacts) -> some View {
        HStack(spacing: 4) {
            Image(systemName: suggestion.isMovedByUser ? "pencil" : "sparkles").font(.caption2)
            Text(suggestion.title).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if suggestion.previousPosition != nil {
                Text("geändert").font(.caption2.weight(.semibold))
            }
            if let priority = facts.priority { PriorityMark(mark: priority) }
        }
    }
}

/// Menu on holding a suggestion (mockup VT1): accept, open the task, dismiss set apart.
struct SuggestionMenu: View {
    var acceptEnabled = true
    let onAccept: () -> Void
    var onOpenTask: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onAccept) { Label("Übernehmen", systemImage: "checkmark") }
            .disabled(!acceptEnabled)
        if let onOpenTask {
            Button(action: onOpenTask) { Label("Aufgabe öffnen", systemImage: "chevron.right") }
        }
        Divider()
        Button(role: .destructive, action: onDismiss) { Label("Verwerfen", systemImage: "xmark") }
    }
}

/// ✓ and ✕ of a row, each with a 44-pt target (mockup VL1).
struct SuggestionButtons: View {
    var acceptEnabled = true
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onAccept) {
                Image(systemName: "checkmark.circle.fill").font(.title2).frame(width: 44, height: 44)
            }
            .disabled(!acceptEnabled)
            .opacity(acceptEnabled ? 1 : 0.35)
            .accessibilityLabel("Übernehmen")
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle").font(.title2).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Verwerfen")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.purple)
    }
}

// MARK: Rows (mockup VL1)

/// A suggestion as a list row, the same in day list, week, month, panel and result sheet: title with
/// P mark, capsules, reason in one line; left of the divider a tap opens the sheet, right ✓ / ✕.
/// Longer days keep their own form (mockup AO1).
struct SuggestionRow: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    /// Opens the suggestion in place (result sheet); without it the row presents the sheet itself.
    var onOpen: (() -> Void)?
    var reasonLines = 1
    @State private var showsSheet = false
    @State private var editing: TaskItem?

    var body: some View {
        let facts = environment.planning.facts(for: suggestion)
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                header(facts)
                if suggestion.kind == .dayChange {
                    Text(SuggestionText.detail(suggestion, planning: environment.planning)).font(.caption).foregroundStyle(.secondary)
                } else {
                    SuggestionCapsules(facts: facts)
                }
                if isWaiting {
                    Label("braucht die längere Arbeitszeit", systemImage: "arrow.turn.down.right").font(.caption2)
                }
                SuggestionStateLabel(suggestion: suggestion)
                if !suggestion.reason.isEmpty && suggestion.kind != .move {
                    Text("„\(suggestion.reason)“").font(.caption).foregroundStyle(.purple).lineLimit(reasonLines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if let onOpen { onOpen() } else { showsSheet = true } }
            Divider().frame(height: 36)
            SuggestionButtons(acceptEnabled: !isWaiting,
                              onAccept: { Task { await environment.planner.accept(suggestion) } },
                              onDismiss: { Task { await environment.planner.dismiss(suggestion) } })
        }
        .padding(.leading, 8)
        .padding(.vertical, 4)
        .background(suggestion.kind == .move ? Color.clear : Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .contextMenu {
            SuggestionMenu(acceptEnabled: !isWaiting,
                           onAccept: { Task { await environment.planner.accept(suggestion) } },
                           onOpenTask: task.map { task in { editing = task } },
                           onDismiss: { Task { await environment.planner.dismiss(suggestion) } })
        }
        .sheet(isPresented: $showsSheet) { SuggestionSheet(suggestion: suggestion) }
        .sheet(item: $editing) { TaskEditorSheet(task: $0) }
    }

    @ViewBuilder
    private func header(_ facts: SuggestionFacts) -> some View {
        HStack(spacing: 4) {
            if suggestion.kind == .move {
                Text(suggestion.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
            } else {
                Label(SuggestionText.title(suggestion, calendar: environment.planning.calendar), systemImage: SuggestionText.symbol(suggestion))
                    .font(.subheadline).foregroundStyle(.purple).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let priority = facts.priority { PriorityMark(mark: priority) }
        }
    }

    private var task: TaskItem? { environment.planning.taskList.items.first { $0.id.key == suggestion.taskKey } }
    private var isWaiting: Bool { SuggestionText.isWaiting(suggestion, planning: environment.planning) }
}

/// A move at the task it concerns (proposal 2026-11-18, §5): the same row, with "↷ nach Fr 20." as first capsule.
struct MoveSuggestionRow: View {
    let suggestion: PlanSuggestion

    var body: some View {
        SuggestionRow(suggestion: suggestion)
    }
}

/// The target day's side of a move (week, §5): a dashed ghost row without facts and buttons.
struct MoveGhostRow: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion

    var body: some View {
        let from = suggestion.fromDay.map { $0.startDate(in: environment.planning.calendar).formatted(.dateTime.weekday(.abbreviated).day()) } ?? ""
        Label("von \(from) · \(suggestion.title)", systemImage: "arrow.uturn.right")
            .font(.subheadline)
            .foregroundStyle(.purple.opacity(0.7))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
    }
}

// MARK: Sheet (mockup VT1)

/// The sheet of one suggestion: when, the task as a card (priority, due date, source, effort bar),
/// the full reason and the decision. The calendar stays visible behind the half-height sheet.
struct SuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let suggestion: PlanSuggestion

    var body: some View {
        NavigationStack {
            SuggestionDetail(suggestion: suggestion, onDone: { dismiss() })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.fraction(0.3), .medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// Content of the suggestion sheet; also a page of the result sheet (mockup VE1). Below the task: moving by
/// hand (mockup VM1) and the conversation about the planning (mockups VK1, VA1).
struct SuggestionDetail: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    let onDone: () -> Void
    @State private var editing: TaskItem?

    private var planning: PlanningModel { environment.planning }
    /// The suggestion as it is now: moving and answers change it while the sheet is open.
    private var live: PlanSuggestion? {
        planning.suggestionBatches.lazy.flatMap(\.suggestions).first { $0.id == suggestion.id }
    }
    private var task: TaskItem? { planning.taskList.items.first { $0.id.key == suggestion.taskKey } }

    var body: some View {
        let current = live ?? suggestion
        let facts = planning.facts(for: current)
        let isWaiting = SuggestionText.isWaiting(current, planning: planning)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SuggestionText.title(current, calendar: planning.calendar)).font(.headline)
                    Label(SuggestionText.sheetWhen(current, calendar: planning.calendar), systemImage: SuggestionText.symbol(current))
                        .font(.subheadline).foregroundStyle(.purple)
                    SuggestionStateLabel(suggestion: current)
                }
            }
            if let task {
                Section {
                    Button { editing = task } label: { TaskCard(task: task, facts: facts) }
                        .buttonStyle(.plain)
                }
            } else if current.kind == .dayChange {
                Section { Text(SuggestionText.detail(current, planning: planning)).foregroundStyle(.secondary) }
            }
            if !current.reason.isEmpty {
                Section("Begründung") {
                    Label("„\(current.reason)“", systemImage: "sparkles").foregroundStyle(.purple)
                }
            }
            if current.kind != .dayChange, live != nil {
                SuggestionMoveSection(suggestion: current)
                if environment.ai.isSignedIn {
                    SuggestionConversation(suggestion: current)
                }
            }
            Section {
            } footer: {
                Text(isWaiting ? "Übernimm zuerst die längere Arbeitszeit."
                     : "Erst „Übernehmen“ legt den Block im Plan-Kalender an.")
            }
        }
        .navigationTitle("Vorschlag")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    Task { await environment.planner.dismiss(current); onDone() }
                } label: { Text("Verwerfen").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered)
                Button {
                    Task { await environment.planner.accept(current); onDone() }
                } label: { Label("Übernehmen", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isWaiting)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(item: $editing) { TaskEditorSheet(task: $0) }
        .onChange(of: live == nil) { _, gone in if gone { onDone() } }
    }
}

/// "✎ von dir verschoben · war 14:00" or "geändert · war 18:00" (mockups VM1, VA1).
struct SuggestionStateLabel: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion

    var body: some View {
        let calendar = environment.planning.calendar
        if let ai = suggestion.aiPosition {
            Label("von dir verschoben · KI: \(Self.difference(ai, suggestion.position, calendar: calendar))", systemImage: "pencil")
                .font(.caption).foregroundStyle(.secondary)
        } else if let previous = suggestion.previousPosition {
            Label("geändert · war \(Self.difference(previous, suggestion.position, calendar: calendar))", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.purple)
        }
    }

    /// The earlier position as far as it differs: "09:00", "30 min" or "Mi 18. 09:00 · 30 min".
    static func difference(_ old: SuggestionPosition, _ new: SuggestionPosition, calendar: Calendar) -> String {
        var parts: [String] = []
        if old.day != new.day || old.kind != new.kind {
            parts.append("\(SuggestionFacts.weekday(old.day, calendar: calendar)) \(old.day.day).")
        }
        if let start = old.startMinutes, start != new.startMinutes || !parts.isEmpty { parts.append(AIPlanner.time(start)) }
        if let minutes = old.minutes, minutes != new.minutes { parts.append(CapacityText.duration(minutes)) }
        return parts.isEmpty ? AIPlanner.positionText(old, calendar: calendar) : parts.joined(separator: " · ")
    }
}

/// Day, start and duration of a suggestion, changeable by hand; it stays a suggestion (mockup VM1).
struct SuggestionMoveSection: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    @State private var error: String?

    private var calendar: Calendar { environment.planning.calendar }

    var body: some View {
        Section {
            DatePicker("Tag", selection: dayBinding, in: environment.planning.today.startDate(in: calendar)..., displayedComponents: .date)
            if suggestion.kind == .block, let start = suggestion.startMinutes, let minutes = suggestion.minutes {
                DatePicker("Beginn", selection: startBinding(start), displayedComponents: .hourAndMinute)
                Stepper(value: durationBinding(minutes), in: 15...(6 * 60), step: 15) {
                    LabeledContent("Dauer", value: CapacityText.duration(minutes))
                }
            }
            if let ai = suggestion.aiPosition {
                Button {
                    Task { await environment.planner.resetSuggestion(suggestion) }
                } label: {
                    Label("Zurück zum Vorschlag der KI (\(AIPlanner.positionText(ai, calendar: calendar)))", systemImage: "arrow.uturn.backward")
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Von Hand ändern")
        } footer: {
            Text(suggestion.kind == .block || suggestion.kind == .move
                 ? "Ein anderer Tag macht aus dem Block eine Verschiebung. Es bleibt ein Vorschlag, bis du ihn übernimmst."
                 : "Es bleibt ein Vorschlag, bis du ihn übernimmst.")
        }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { suggestion.day.startDate(in: calendar) }, set: { date in
            move(day: PlanDay(date: date, calendar: calendar), start: nil, minutes: nil)
        })
    }

    private func startBinding(_ start: Int) -> Binding<Date> {
        let dayStart = suggestion.day.startDate(in: calendar)
        return Binding(get: { dayStart.addingTimeInterval(TimeInterval(start * 60)) }, set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            move(day: suggestion.day, start: minutes / 5 * 5, minutes: suggestion.minutes)
        })
    }

    private func durationBinding(_ minutes: Int) -> Binding<Int> {
        Binding(get: { minutes }, set: { move(day: suggestion.day, start: suggestion.startMinutes, minutes: $0) })
    }

    private func move(day: PlanDay, start: Int?, minutes: Int?) {
        Task { error = await environment.planner.moveSuggestion(suggestion, day: day, start: start, minutes: minutes) }
    }
}

/// Talking about the suggestion (mockups VK1, VA1): the exchange of this planning, the change card of the
/// last answer with "Rückgängig" and "Als Vorgabe merken", quick replies and the input line.
struct SuggestionConversation: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    @State private var text = ""
    @State private var rule: String?
    @FocusState private var isFocused: Bool

    static let quickReplies = ["Früher am Tag", "Anderer Tag", "Kürzer"]

    private var planner: AIPlanner { environment.planner }
    private var batch: SuggestionBatch? {
        environment.planning.suggestionBatches.first { $0.suggestions.contains { $0.id == suggestion.id } }
    }
    private var isSending: Bool { planner.revisingID == suggestion.id }

    var body: some View {
        Section {
            ForEach(batch?.conversation ?? []) { message in
                if message.role == .user {
                    Text(message.text)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(.secondary)
                } else {
                    answer(message, isLast: message.id == batch?.conversation?.last?.id)
                }
            }
            if isSending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("ChatGPT antwortet …").foregroundStyle(.secondary)
                }
            } else if let error = planner.revisionError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.quickReplies, id: \.self) { reply in
                        Button(reply) { send(reply) }
                            .buttonStyle(.bordered)
                            .tint(.purple)
                            .disabled(isSending)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Zum Vorschlag etwas sagen …", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit { send(text) }
                Button {
                    send(text)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.purple)
                .disabled(isSending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Senden")
            }
        } header: {
            Label("Mit ChatGPT besprechen", systemImage: "sparkles")
        } footer: {
            Text("Senden gibt diesen Vorschlag, die übrigen der Planung, deine Änderungen, deine Vorgaben und die Termine dieser Tage an ChatGPT.")
        }
        .alert("Als Vorgabe merken", isPresented: Binding(get: { rule != nil }, set: { if !$0 { rule = nil } })) {
            TextField("Vorgabe", text: Binding(get: { rule ?? "" }, set: { rule = $0 }))
            Button("Merken") { remember() }
            Button("Abbrechen", role: .cancel) { rule = nil }
        } message: {
            Text("Nenne, woran die KI die Aufgaben erkennt, z. B. „Aufgaben aus der Liste Studium nicht nach 18 Uhr“. Vorgaben gelten ohne Gewähr.")
        }
    }

    @ViewBuilder
    private func answer(_ message: SuggestionMessage, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let changes = message.changes ?? []
            Label(changes.isEmpty ? "Nichts geändert" : (changes.count == 1 ? "1 Vorschlag geändert" : "\(changes.count) Vorschläge geändert"),
                  systemImage: "sparkles")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.purple)
            ForEach(changes, id: \.self) { Text($0).font(.caption) }
            ForEach(message.rejected ?? [], id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if !message.text.isEmpty {
                Text("„\(message.text)“").font(.caption).foregroundStyle(.purple)
            }
            if isLast {
                HStack(spacing: 12) {
                    if batch?.revisionUndo != nil && !changes.isEmpty {
                        Button("Rückgängig") {
                            guard let id = batch?.id else { return }
                            Task { await planner.undoRevision(of: id) }
                        }
                    }
                    if environment.settings.aiPlanningRules.count < AppSettings.maximumPlanningRules {
                        Button {
                            rule = lastComment
                        } label: {
                            Label("Als Vorgabe merken", systemImage: "plus")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var lastComment: String {
        batch?.conversation?.last { $0.role == .user }?.text ?? ""
    }

    private func send(_ comment: String) {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty, !isSending else { return }
        text = ""
        isFocused = false
        Task { await planner.revise(suggestion, comment: comment) }
    }

    private func remember() {
        let sentence = (rule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        rule = nil
        guard !sentence.isEmpty else { return }
        environment.settings.aiPlanningRules.append(sentence)
    }
}

/// The task as a card (mockup VT1): priority, due date with distance, source, effort bar; the whole card
/// opens the editor.
struct TaskCard: View {
    let task: TaskItem
    let facts: SuggestionFacts

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let priority = facts.priority { PriorityMark(mark: priority) }
                if let due = facts.due {
                    FactCapsule(text: [due.text, facts.dueDistance].compactMap { $0 }.uniqued().joined(separator: " · "),
                                symbol: "flag.fill", urgency: due.urgency)
                }
                Spacer(minLength: 0)
            }
            Text(([task.container.name] + task.subContainers.map(\.name)).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let bar = facts.bar {
                EffortBar(bar: bar)
            } else if let effort = facts.effort {
                Text("Aufwand \(effort)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Aufgabe öffnen").font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }
}

/// Planned (green), this suggestion (purple) and open (grey) of the task's effort.
struct EffortBar: View {
    let bar: SuggestionFacts.Bar

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Aufwand \(CapacityText.duration(bar.total))").font(.caption.weight(.semibold))
                Spacer()
                Text("danach \(CapacityText.duration(min(bar.total, bar.planned + bar.suggested))) von \(CapacityText.duration(bar.total)) geplant")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let total = CGFloat(max(bar.total, bar.planned + bar.suggested, 1))
                HStack(spacing: 1) {
                    Rectangle().fill(.green).frame(width: proxy.size.width * CGFloat(bar.planned) / total)
                    Rectangle().fill(.purple).frame(width: proxy.size.width * CGFloat(bar.suggested) / total)
                    Rectangle().fill(Color.secondary.opacity(0.25))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            Text([bar.planned > 0 ? "\(CapacityText.duration(bar.planned)) eingeplant" : nil,
                  "+\(CapacityText.duration(bar.suggested)) dieser Vorschlag",
                  bar.open > 0 ? "\(CapacityText.duration(bar.open)) offen" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// The existing task editor as a sheet over another sheet (mockup VT1, "Aufgabe öffnen").
struct TaskEditorSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let task: TaskItem

    var body: some View {
        if let provider = environment.taskList.provider(for: task.id.source) {
            TaskEditorView(item: task, provider: provider, calendar: environment.taskList.calendar, containers: [],
                           onDelete: { version in Task { await environment.taskList.delete(task.id, version: version) } },
                           planning: environment.planning) { saved in
                environment.taskList.didSave(saved)
                Task { await environment.planning.reload() }
            }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
