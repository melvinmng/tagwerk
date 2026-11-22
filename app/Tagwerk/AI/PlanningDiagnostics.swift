import SwiftUI
import TagwerkCore

/// Numbers of one planning run for tuning the selection rules (proposal 2026-11-18, §6). No titles, no IDs.
struct PlanningRunLog: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var scope: String
    var tasksSent: Int
    var omitted: Int
    var freeMinutes: Int
    var inputCharacters: Int
    var model: String
    var seconds: Double
    var retried: Bool
    var blocks: Int
    var assignments: Int
    var moves: Int
    var dayChanges: Int
    var addedP1: Int
    var violations: [String: Int]
    var overbookedBefore: Int
}

/// Keeps the last 50 runs on this device (UserDefaults; numbers only).
@MainActor
final class PlanningDiagnostics {
    static let shared = PlanningDiagnostics()
    static let key = "tagwerk.aiPlanningRuns"
    static let limit = 50
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var runs: [PlanningRunLog] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PlanningRunLog].self, from: data)) ?? []
    }

    func append(_ run: PlanningRunLog) {
        let all = Array((runs + [run]).suffix(Self.limit))
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// Settings › KI › Diagnose: the logged numbers, newest first.
struct PlanningDiagnosticsView: View {
    @State private var runs: [PlanningRunLog] = []

    var body: some View {
        List {
            if runs.isEmpty {
                Text("Noch keine Planung protokolliert.").foregroundStyle(.secondaryText)
            }
            ForEach(runs.reversed()) { run in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(run.date.formatted(date: .abbreviated, time: .shortened)) · \(run.scope) · \(run.model)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(run.tasksSent) Aufgaben gesendet, \(run.omitted) gekürzt · \(run.freeMinutes) min frei · \(run.inputCharacters) Zeichen")
                    Text("\(String(format: "%.1f", run.seconds)) s\(run.retried ? " · mit Nachfrage" : "") · Überbuchung vorher \(run.overbookedBefore) min")
                    Text("Vorschläge: \(run.blocks) Blöcke, \(run.assignments) Tage, \(run.moves) verschieben, \(run.dayChanges) länger, \(run.addedP1) P1 ergänzt")
                    if !run.violations.isEmpty {
                        Text("Verstöße: " + run.violations.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
                    }
                }
                .font(.caption)
            }
        }
        .navigationTitle("Diagnose")
        .toolbar {
            Button("Leeren", role: .destructive) {
                PlanningDiagnostics.shared.clear()
                runs = []
            }
        }
        .task { runs = PlanningDiagnostics.shared.runs }
    }
}
