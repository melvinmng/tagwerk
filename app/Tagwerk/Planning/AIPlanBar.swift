import AIKit
import SwiftUI
import TagwerkCore

/// The AI planning bar (mockups V1, Y1/Y2, Z1, Z3): one row group that appears as the foot of the day's
/// capacity card and as a flat card under the header in week and month. Nothing is sent without a tap (§8.4).
struct AIPlanBar: View {
    @Environment(AppEnvironment.self) private var environment
    let scope: PlanScope
    @State private var showsResult = false

    private var planner: AIPlanner { environment.planner }
    private var planning: PlanningModel { environment.planning }
    /// Only the results of this kind of plan: the day shows the day plan, week and month the period plan.
    private var batches: [SuggestionBatch] {
        planning.suggestionBatches.filter { ($0.scope == .day) == (scope == .day) }
    }
    private var suggestions: [PlanSuggestion] { batches.flatMap(\.suggestions) }
    private var unscheduledCount: Int { batches.reduce(0) { $0 + $1.unscheduled.count } }
    private var riskCount: Int { batches.reduce(0) { $0 + $1.risks.count } }

    /// Hidden when the whole period lies in the past.
    var isVisible: Bool { planning.days.contains { !$0.isPast } }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .font(.subheadline)
            .sheet(isPresented: $showsResult) { PlanResultSheet(scope: scope) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !environment.ai.isSignedIn {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Mit ChatGPT planen: in Einstellungen › KI anmelden").foregroundStyle(.secondary)
            }
        } else if planner.isPlanning {
            HStack(spacing: 8) {
                ProgressView()
                Text(Self.progressText(scope)).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") { planner.cancel() }
            }
        } else {
            if case .failed(let message) = planner.state {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let notice = planner.notice {
                Text(notice).foregroundStyle(.secondary)
            }
            if suggestions.isEmpty && unscheduledCount == 0 && riskCount == 0 {
                actions(retry: isFailed)
            } else {
                summary
                actions(retry: isFailed)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = planner.state { return true }
        return false
    }

    /// "✦ 2 Vorschläge · 1 h 45   Verwerfen" and the orange line for left-out tasks and risks.
    @ViewBuilder
    private var summary: some View {
        if let text = batches.compactMap(\.summary).last {
            Label(text, systemImage: "sparkles").font(.subheadline).foregroundStyle(.primary)
        }
        // In the day, longer hours and moves are rows of the bar (mockup AO1); the grid shows the blocks.
        if scope == .day {
            ForEach(suggestions.filter { $0.kind == .dayChange }) { suggestion in
                SuggestionRow(suggestion: suggestion)
            }
            let moves = suggestions.filter { $0.kind == .move }
            if !moves.isEmpty {
                // The moves themselves sit at their task rows in the panel (proposal §5).
                let relieved = moves.compactMap { move in
                    planning.taskList.items.first { $0.id.key == move.taskKey }
                        .map { $0.estimateMinutes ?? planning.defaultTaskMinutes }
                }.reduce(0, +)
                Label("\(moves.count) verschieben · \(CapacityText.duration(relieved)) entlastet", systemImage: "arrow.uturn.right")
                    .foregroundStyle(.purple)
            }
        }
        HStack {
            if suggestions.isEmpty {
                Label("Keine Vorschläge", systemImage: "sparkles").foregroundStyle(.secondary)
            } else {
                Label {
                    Text(suggestionText)
                } icon: {
                    Image(systemName: "sparkles")
                }
                .foregroundStyle(.purple)
            }
            Spacer()
            Button("Verwerfen") { Task { await planner.dismissAll(scope: scope) } }
                .foregroundStyle(.secondary)
        }
        if unscheduledCount + riskCount > 0 {
            Button {
                showsResult = true
            } label: {
                HStack {
                    Label(leftOutText, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func actions(retry: Bool) -> some View {
        if suggestions.contains(where: { $0.kind == .dayChange }) {
            Text("„Alle übernehmen“ übernimmt zuerst die längere Arbeitszeit.").font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 10) {
            if !suggestions.isEmpty {
                Button {
                    Task { await planner.acceptAll(scope: scope) }
                } label: {
                    Label("Alle übernehmen (\(suggestions.count))", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                Button("Neu planen") { start() }
                    .buttonStyle(.bordered)
            } else if retry {
                Button("Erneut versuchen") { Task { await planner.retry() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            } else {
                Button {
                    start()
                } label: {
                    Label(Self.planTitle(scope), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            }
        }
    }

    private func start() {
        planner.notice = nil
        planner.start(scope: scope, anchor: planning.anchor)
    }

    private var suggestionText: String {
        let minutes = suggestions.compactMap(\.minutes).reduce(0, +)
        let count = String(localized: "\(suggestions.count) Vorschläge")
        return minutes > 0 ? "\(count) · \(CapacityText.duration(minutes))" : count
    }

    private var leftOutText: String {
        var parts: [String] = []
        if unscheduledCount > 0 { parts.append(String(localized: "\(unscheduledCount) nicht eingeplant")) }
        if riskCount > 0 { parts.append(String(localized: "\(riskCount) Risiken")) }
        return parts.joined(separator: " · ")
    }

    static func actionName(_ scope: PlanScope) -> String {
        switch scope {
        case .day: String(localized: "Tag")
        case .week: String(localized: "Woche")
        case .month: String(localized: "Monat")
        }
    }

    /// The button that starts planning: a whole sentence per scope, so that translations can inflect it.
    static func planTitle(_ scope: PlanScope) -> String {
        switch scope {
        case .day: String(localized: "Tag planen")
        case .week: String(localized: "Woche planen")
        case .month: String(localized: "Monat planen")
        }
    }

    static func progressText(_ scope: PlanScope) -> String {
        switch scope {
        case .day: String(localized: "ChatGPT plant den Tag …")
        case .week: String(localized: "ChatGPT plant die Woche …")
        case .month: String(localized: "ChatGPT plant den Monat …")
        }
    }
}

/// Result sheet (mockups Z1, VE1): open suggestions as rows with their facts, left-out tasks with
/// priority, due date and open effort, and risks. A suggestion opens as the next page of the sheet.
struct PlanResultSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let scope: PlanScope
    @State private var path: [PlanSuggestion] = []
    @State private var editing: TaskItem?

    private var batches: [SuggestionBatch] {
        environment.planning.suggestionBatches.filter { ($0.scope == .day) == (scope == .day) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let suggestions = batches.flatMap(\.suggestions)
                if !suggestions.isEmpty {
                    Section("Vorschläge") {
                        ForEach(suggestions) { suggestion in
                            SuggestionRow(suggestion: suggestion, onOpen: { path.append(suggestion) }, reasonLines: 3)
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                    }
                }
                let unscheduled = batches.flatMap(\.unscheduled)
                if !unscheduled.isEmpty {
                    Section("Nicht eingeplant") {
                        ForEach(unscheduled, id: \.taskKey) { entry in
                            Button { open(entry) } label: { UnscheduledRow(entry: entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                let risks = batches.flatMap(\.risks)
                if !risks.isEmpty {
                    Section("Risiken") {
                        ForEach(risks, id: \.self) { risk in
                            Label(risk, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Ergebnis der Planung")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PlanSuggestion.self) { suggestion in
                SuggestionDetail(suggestion: suggestion, onDone: { path.removeAll() })
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        .sheet(item: $editing) { TaskEditorSheet(task: $0) }
    }

    private func open(_ entry: UnscheduledTask) {
        editing = environment.planning.taskList.items.first { $0.id.key == entry.taskKey }
    }
}

/// A left-out task (mockup VE1): title with P mark, due date and open effort, reason; a tap opens the task.
struct UnscheduledRow: View {
    @Environment(AppEnvironment.self) private var environment
    let entry: UnscheduledTask

    var body: some View {
        let facts = environment.planning.facts(for: entry)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(entry.title).lineLimit(2)
                    Spacer(minLength: 0)
                    if let priority = facts.priority { PriorityMark(mark: priority) }
                }
                SuggestionCapsules(facts: facts)
                Text(entry.reason).font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Short texts for suggestions.
enum SuggestionText {
    static func symbol(_ suggestion: PlanSuggestion) -> String {
        switch suggestion.kind {
        case .dayChange: "clock.badge"
        case .move: "arrow.uturn.right"
        case .block, .assignment: "sparkles"
        }
    }

    /// "Mi 09:00 bis 20:00 arbeiten", "Blumen gießen → Do 19." or the task title.
    static func title(_ suggestion: PlanSuggestion, calendar: Calendar) -> String {
        switch suggestion.kind {
        case .move:
            "\(suggestion.title) → \(suggestion.day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).day()))"
        case .dayChange, .block, .assignment:
            suggestion.title
        }
    }

    @MainActor
    static func detail(_ suggestion: PlanSuggestion, planning: PlanningModel) -> String {
        switch suggestion.kind {
        case .dayChange:
            guard let start = suggestion.startMinutes, let end = suggestion.endMinutes else { return String(localized: "Vorschlag") }
            let current = planning.workHours(on: suggestion.day)?.minutes ?? 0
            let added = (end - start) - current
            return current == 0 ? String(localized: "Vorschlag · freier Tag · \(CapacityText.duration(end - start))")
                : String(localized: "Vorschlag · +\(CapacityText.duration(max(0, added))) · nur an diesem Tag")
        case .move:
            return [String(localized: "Vorschlag · verschieben"), due(suggestion, planning: planning)].compactMap { $0 }.joined(separator: " · ")
        case .block, .assignment:
            var parts = [String(localized: "Vorschlag")]
            if let start = suggestion.startMinutes { parts.append(DateText.time(minutes: start, calendar: planning.calendar)) }
            if let minutes = suggestion.minutes { parts.append(CapacityText.duration(minutes)) }
            if let due = due(suggestion, planning: planning) { parts.append(due) }
            return parts.joined(separator: " · ")
        }
    }

    /// "fällig 20.11." / "überfällig seit 15.11." for the suggestion's task, if it has a due date.
    @MainActor
    static func due(_ suggestion: PlanSuggestion, planning: PlanningModel) -> String? {
        guard let due = planning.taskList.items.first(where: { $0.id.key == suggestion.taskKey })?.due else { return nil }
        let day = PlanDay(due)
        let text = day.startDate(in: planning.calendar).formatted(.dateTime.day().month(.twoDigits))
        return day < planning.today ? String(localized: "überfällig seit \(text)") : String(localized: "fällig \(text)")
    }

    /// A block whose longer day is still open (mockup AB1).
    @MainActor
    static func isWaiting(_ suggestion: PlanSuggestion, planning: PlanningModel) -> Bool {
        guard let change = suggestion.dependsOn else { return false }
        return planning.suggestionBatches.contains { $0.suggestions.contains { $0.id == change } }
    }

    /// Head line of the sheet: "Vorschlag · Mi 18. Nov. · 18:00 bis 18:45", "von Mi 18. nach Fr 20.".
    static func sheetWhen(_ suggestion: PlanSuggestion, calendar: Calendar) -> String {
        let date = suggestion.day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        switch suggestion.kind {
        case .move:
            let to = SuggestionFacts.weekdayDay(suggestion.day, calendar: calendar)
            guard let from = suggestion.fromDay else { return String(localized: "nach \(to)") }
            let origin = SuggestionFacts.weekdayDay(from, calendar: calendar)
            return String(localized: "von \(origin) nach \(to)")
        case .dayChange:
            guard let start = suggestion.startMinutes, let end = suggestion.endMinutes else {
                return String(localized: "Vorschlag · \(date)")
            }
            let from = DateText.time(minutes: start, calendar: calendar), to = DateText.time(minutes: end, calendar: calendar)
            return String(localized: "Vorschlag · \(date) · \(from) bis \(to)")
        case .block, .assignment:
            guard let start = suggestion.startMinutes, let minutes = suggestion.minutes else {
                return String(localized: "Vorschlag · \(date)")
            }
            let from = DateText.time(minutes: start, calendar: calendar)
            let to = DateText.time(minutes: start + minutes, calendar: calendar)
            return String(localized: "Vorschlag · \(date) · \(from) bis \(to)")
        }
    }

    /// VoiceOver text of a grid block.
    static func accessibility(_ suggestion: PlanSuggestion, facts: SuggestionFacts, time: String) -> String {
        [String(localized: "Vorschlag"), suggestion.title, time, facts.priority?.text, facts.due?.text, facts.effort]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// "Mi 18.11. · 14:00 · 45 min" for blocks, "Do 19.11." for work days.
    static func when(_ suggestion: PlanSuggestion, calendar: Calendar) -> String {
        let date = suggestion.day.startDate(in: calendar)
        var parts = [date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits))]
        if let start = suggestion.startMinutes { parts.append(DateText.time(minutes: start, calendar: calendar)) }
        if let minutes = suggestion.minutes { parts.append(CapacityText.duration(minutes)) }
        return parts.joined(separator: " · ")
    }
}
