import SwiftUI
import TagwerkCore

/// "Vorschlag übernehmen": the habits of the former tracker that are still missing, each with a tick. Every automatic
/// source serves one habit and at most `HabitRules.maximumActive` habits are active; what does not fit is said before.
struct HabitSuggestionSheet: View {
    let model: HabitsModel
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [HabitSuggestion] = []
    @State private var selected: Set<String> = []
    @State private var isLoaded = false

    var body: some View {
        let chosen = suggestions.filter { selected.contains($0.key) }
        let plan = HabitSuggestions.plan(selected: chosen, existing: model.habits)
        NavigationStack {
            Form {
                Section {
                    ForEach(suggestions) { suggestion in
                        Button {
                            if selected.contains(suggestion.key) { selected.remove(suggestion.key) } else { selected.insert(suggestion.key) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(suggestion.key) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(suggestion.key) ? Color.accentColor : Color.secondary)
                                Image(systemName: suggestion.symbol).frame(width: 24).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name).foregroundStyle(.primary)
                                    if let note = note(for: suggestion, in: plan) {
                                        Text(note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(suggestion.key) ? .isSelected : [])
                    }
                } footer: {
                    Text("Höchstens \(HabitRules.maximumActive) aktive Gewohnheiten. Jede automatische Quelle gilt für höchstens eine Gewohnheit; ist sie schon vergeben, hakst du die Gewohnheit von Hand ab.")
                }
            }
            .navigationTitle("Vorschlag übernehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        model.adopt(chosen)
                        dismiss()
                    }
                    .disabled(plan.adoptions.isEmpty)
                }
            }
            .onAppear {
                guard !isLoaded else { return }
                isLoaded = true
                // The names are read now, so they follow the language of this moment.
                suggestions = model.missingSuggestions
                selected = Set(suggestions.map(\.key))
            }
        }
    }

    /// The line under a name: that it will be ticked by hand, or that it no longer fits.
    private func note(for suggestion: HabitSuggestion, in plan: HabitSuggestions.Plan) -> String? {
        if plan.leftOut.contains(where: { $0.key == suggestion.key }) {
            return String(localized: "Passt nicht mehr dazu: Pausiere oder lösche eine Gewohnheit.")
        }
        if let adoption = plan.adoptions.first(where: { $0.suggestion.key == suggestion.key }) {
            if adoption.fellBackToManual {
                return String(localized: "Quelle schon vergeben: Du hakst sie von Hand ab.")
            }
            if suggestion.source != .manual { return HabitText.sourceTitle(suggestion.source) }
        }
        return nil
    }
}
