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
    private var batches: [SuggestionBatch] { planning.suggestionBatches }
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
            .sheet(isPresented: $showsResult) { PlanResultSheet() }
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
                Text("ChatGPT plant \(Self.periodName(scope)) …").foregroundStyle(.secondary)
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
            ForEach(suggestions.filter { $0.kind == .dayChange || $0.kind == .move }) { suggestion in
                SuggestionRow(suggestion: suggestion)
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
            Button("Verwerfen") { Task { await planner.dismissAll() } }
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
                    Task { await planner.acceptAll() }
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
                    Label("\(Self.actionName(scope)) planen", systemImage: "sparkles")
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
        let count = suggestions.count == 1 ? "1 Vorschlag" : "\(suggestions.count) Vorschläge"
        return minutes > 0 ? "\(count) · \(CapacityText.duration(minutes))" : count
    }

    private var leftOutText: String {
        var parts: [String] = []
        if unscheduledCount > 0 { parts.append("\(unscheduledCount) nicht eingeplant") }
        if riskCount > 0 { parts.append(riskCount == 1 ? "1 Risiko" : "\(riskCount) Risiken") }
        return parts.joined(separator: " · ")
    }

    static func actionName(_ scope: PlanScope) -> String {
        switch scope {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        }
    }

    static func periodName(_ scope: PlanScope) -> String {
        switch scope {
        case .day: "den Tag"
        case .week: "die Woche"
        case .month: "den Monat"
        }
    }
}

/// Result sheet (mockup Z1): open suggestions, left-out tasks with reason and risks.
struct PlanResultSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private var batches: [SuggestionBatch] { environment.planning.suggestionBatches }

    var body: some View {
        NavigationStack {
            List {
                let suggestions = batches.flatMap(\.suggestions)
                if !suggestions.isEmpty {
                    Section("Vorschläge") {
                        ForEach(suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                Text(SuggestionText.when(suggestion, calendar: environment.planning.calendar))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !suggestion.reason.isEmpty {
                                    Text("„\(suggestion.reason)“").font(.caption).foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                }
                let unscheduled = batches.flatMap(\.unscheduled)
                if !unscheduled.isEmpty {
                    Section("Nicht eingeplant") {
                        ForEach(unscheduled, id: \.taskKey) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                Text(entry.reason).font(.caption).foregroundStyle(.secondary)
                            }
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
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
            guard let start = suggestion.startMinutes, let end = suggestion.endMinutes else { return "Vorschlag" }
            let current = planning.workHours(on: suggestion.day)?.minutes ?? 0
            let added = (end - start) - current
            return current == 0 ? "Vorschlag · freier Tag · \(CapacityText.duration(end - start))"
                : "Vorschlag · +\(CapacityText.duration(max(0, added))) · nur an diesem Tag"
        case .move:
            return "Vorschlag · verschieben"
        case .block, .assignment:
            var parts = ["Vorschlag"]
            if let start = suggestion.startMinutes { parts.append(AIPlanner.time(start)) }
            if let minutes = suggestion.minutes { parts.append(CapacityText.duration(minutes)) }
            return parts.joined(separator: " · ")
        }
    }

    /// A block whose longer day is still open (mockup AB1).
    @MainActor
    static func isWaiting(_ suggestion: PlanSuggestion, planning: PlanningModel) -> Bool {
        guard let change = suggestion.dependsOn else { return false }
        return planning.suggestionBatches.contains { $0.suggestions.contains { $0.id == change } }
    }

    /// "Mi 18.11. · 14:00 · 45 min" for blocks, "Do 19.11." for work days.
    static func when(_ suggestion: PlanSuggestion, calendar: Calendar) -> String {
        let date = suggestion.day.startDate(in: calendar)
        var parts = [date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits))]
        if let start = suggestion.startMinutes { parts.append(AIPlanner.time(start)) }
        if let minutes = suggestion.minutes { parts.append(CapacityText.duration(minutes)) }
        return parts.joined(separator: " · ")
    }
}
