import SwiftUI
import TagwerkCore

/// "Künftig immer" rules for merging placeholder or identical events; each can be deleted.
struct MergeRulesView: View {
    let model: PlanningModel
    @State private var rules: [(key: String, title: String, calendar: String, merges: Bool)] = []

    var body: some View {
        List {
            Section {
                if rules.isEmpty { Text("Keine Regeln").foregroundStyle(.secondaryText) }
                ForEach(rules, id: \.key) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("„\(rule.title)“ aus „\(rule.calendar)“")
                        Text(rule.merges ? "wird immer zusammengefasst" : "bleibt immer getrennt")
                            .font(.caption).foregroundStyle(.secondaryText)
                    }
                    .swipeActions {
                        Button("Löschen", role: .destructive) { delete(rule.key) }
                    }
                }
            } footer: {
                Text("Entstehen über „Künftig immer“ auf einer Vorschlagskarte. Nach dem Löschen fragt Tagwerk wieder.")
            }
        }
        .navigationTitle("Zusammenfassen-Regeln")
        .task { rules = model.mergeRules() }
    }

    private func delete(_ key: String) {
        Task {
            await model.deleteMergeRule(key: key)
            rules = model.mergeRules()
        }
    }
}
