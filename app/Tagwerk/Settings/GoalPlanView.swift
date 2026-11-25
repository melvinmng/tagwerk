import SwiftUI
import TagwerkCore

/// The goals beyond the basic ones, and the plans that held before (decision ZI5b). Edits create a plan that holds from today, like
/// the basic goals on the page before.
struct GoalPlanView: View {
    let editor: GoalPlanEditor
    @Environment(AppEnvironment.self) private var environment

    private func goal(_ keyPath: WritableKeyPath<GoalPlan, Int?>, orStart start: Int) -> Binding<Int> {
        Binding(get: { editor.plan[keyPath: keyPath] ?? start }, set: { editor.set(keyPath, to: $0) })
    }

    private func isOn(_ keyPath: WritableKeyPath<GoalPlan, Int?>, start: Int) -> Binding<Bool> {
        Binding(get: { editor.plan[keyPath: keyPath] != nil }, set: { editor.set(keyPath, to: $0 ? start : nil) })
    }

    /// The start of a new target: the 7-day mean of the weight or, without one, the last weight.
    private var startWeight: Double { environment.capture.weightOverview.mean ?? environment.capture.weightOverview.latest ?? 75 }

    var body: some View {
        Form {
            GoalPlanningEntries(offer: .planOnly)
            Section {
                Toggle("Kohlenhydrate-Ziel", isOn: isOn(\.carbsGrams, start: 250))
                if editor.plan.carbsGrams != nil {
                    ValueStepper("Kohlenhydrate", value: goal(\.carbsGrams, orStart: 250), in: GoalRanges.carbsGrams, step: 5, unit: "g") {
                        IntakeFormat.grams(Double($0), estimated: false)
                    }
                }
                Toggle("Fett-Ziel", isOn: isOn(\.fatGrams, start: 70))
                if editor.plan.fatGrams != nil {
                    ValueStepper("Fett", value: goal(\.fatGrams, orStart: 70), in: GoalRanges.fatGrams, step: 5, unit: "g") {
                        IntakeFormat.grams(Double($0), estimated: false)
                    }
                }
            } header: {
                Text("Kohlenhydrate und Fett")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Diese Ziele gelten für einen Tag ohne angerechnete Aktivität. Mit angerechneter Aktivität wachsen Kohlenhydrate und Fett im Verhältnis ihrer Kalorien; Eiweiß und Ballaststoffe bleiben fest.")
                    .foregroundStyle(.secondaryText)
            }

            Section {
                Toggle("Ballaststoff-Ziel", isOn: isOn(\.fiberGrams, start: 30))
                if editor.plan.fiberGrams != nil {
                    ValueStepper("Ballaststoffe", value: goal(\.fiberGrams, orStart: 30), in: GoalRanges.fiberGrams, step: 1, unit: "g") {
                        IntakeFormat.grams(Double($0), estimated: false)
                    }
                }
                Toggle("Zucker-Obergrenze", isOn: isOn(\.sugarLimitGrams, start: 50))
                if editor.plan.sugarLimitGrams != nil {
                    ValueStepper("Zucker, höchstens", value: goal(\.sugarLimitGrams, orStart: 50), in: GoalRanges.sugarLimitGrams, step: 5, unit: "g") {
                        IntakeFormat.grams(Double($0), estimated: false)
                    }
                }
            } header: {
                Text("Ballaststoffe und Zucker")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Ohne Ziel zeigt die Karte „Nährwerte“ nur den Wert. Zucker hat eine Obergrenze: Darüber wird der Balken orange.")
                    .foregroundStyle(.secondaryText)
            }

            Section {
                Toggle("Zielgewicht", isOn: Binding(get: { editor.plan.targetWeightKg != nil },
                                                    set: { editor.set(\.targetWeightKg, to: $0 ? WeightRules.clamped(startWeight) : nil) }))
                    .accessibilityIdentifier("targetWeightEnabled")
                if let target = editor.plan.targetWeightKg {
                    ValueStepper("Zielgewicht", value: Binding(get: { target }, set: { editor.set(\.targetWeightKg, to: WeightRules.clamped($0)) }),
                                 in: GoalRanges.targetWeightKg, step: WeightRules.stepKilograms,
                                 kind: .decimal(fractionDigits: 1), unit: "kg") { WeightFormat.kilograms($0) }
                }
            } header: {
                Text("Gewicht")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Das Zielgewicht erscheint als gestrichelte Linie im Gewichtsverlauf, bei „Verlauf und Ziele“. Es ändert dein Tagesbudget nicht.")
                    .foregroundStyle(.secondaryText)
            }

            Section {
                LabeledContent("Gilt ab") {
                    Text(CaptureText.date(editor.plan.validFrom, calendar: environment.capture.calendar))
                }
                ForEach(editor.earlierPlans) { plan in
                    LabeledContent {
                        Text(IntakeFormat.kcal(Double(plan.kcal), estimated: false)).monospacedDigit()
                    } label: {
                        Text("Bis \(CaptureText.date(plan.validFrom.adding(days: -1, calendar: environment.capture.calendar), calendar: environment.capture.calendar))")
                    }
                }
            } header: {
                Text("Zielstände")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Eine Änderung gilt ab heute. Frühere Tage, auch im Wochenrückblick, rechnen mit dem Stand, der damals galt.")
                    .foregroundStyle(.secondaryText)
            }
        }
        .navigationTitle("Weitere Ziele")
        .navigationBarTitleDisplayMode(.inline)
    }
}
