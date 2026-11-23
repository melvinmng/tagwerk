import SwiftUI
import TagwerkCore

/// "Aktiv heute": what the active energy of the shown day consists of and how much of it counts towards the budget (mockup BU4b).
struct BudgetBreakdownSheet: View {
    let model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let data = model.current
        let breakdown = ActiveBreakdown.make(budget: data.figures.budget, workouts: data.workouts)
        NavigationStack {
            List {
                Section {
                    LabeledContent("Aktiv gesamt") {
                        Text(kcal(breakdown.totalKcal)).monospacedDigit()
                    }
                    if !breakdown.isFromHealth {
                        Text(breakdown.gapKcal > 0
                             ? "Health liefert keine Aktivität. Es zählen nur Trainings aus Tagwerk."
                             : "Health liefert keine Aktivität. Ohne Erlaubnis oder ohne Daten bleibt dieser Wert leer.")
                            .font(.subheadline).foregroundStyle(.secondaryText)
                    }
                }
                if !breakdown.workouts.isEmpty {
                    Section("Trainings") {
                        ForEach(breakdown.workouts) { workout in
                            LabeledContent {
                                Text(kcal(workout.kilocalories ?? 0)).monospacedDigit()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.displayName)
                                    Text(workout.sourceName ?? String(localized: "Tagwerk")).font(.caption).foregroundStyle(.secondaryText)
                                }
                            }
                        }
                    }
                }
                if breakdown.everydayKcal != nil || breakdown.gapKcal > 0 {
                    Section {
                        if let everyday = breakdown.everydayKcal {
                            LabeledContent("Alltag") { Text(kcal(everyday)).monospacedDigit() }
                        }
                        if breakdown.gapKcal > 0 {
                            LabeledContent("Eigene Trainings, noch nicht in Health") { Text(kcal(breakdown.gapKcal)).monospacedDigit() }
                        }
                    } footer: {
                        Text("Alltag ist der Rest der Aktivität aus Health ohne die Trainings oben.")
                    }
                }
                Section {
                    LabeledContent("Anteil") {
                        Text(breakdown.creditPercent == 0 ? String(localized: "aus") : "\(breakdown.creditPercent) %").monospacedDigit()
                    }
                    LabeledContent("Angerechnet") { Text(kcal(Double(breakdown.creditedKcal))).monospacedDigit().fontWeight(.semibold) }
                } footer: {
                    Text("Die Aktivität ist ein Schätzwert deiner Geräte. Den Anteil, der dein Tagesbudget erhöht, änderst du unter Einstellungen › Erfassen.")
                }
            }
            .navigationTitle(title(for: data.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Capture.breakdown)
        .presentationDetents([.medium, .large])
    }

    private func title(for day: PlanDay) -> String {
        day == model.today ? String(localized: "Aktiv heute")
            : String(localized: "Aktiv · \(CaptureText.date(day, calendar: model.calendar))")
    }

    private func kcal(_ value: Double) -> String { String(localized: "\(IntakeFormat.grouped(Int(value.rounded()))) kcal") }
}
