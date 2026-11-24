import HealthBridge
import SwiftUI
import TagwerkCore

/// Einstellungen › Erfassen (mockup E6a, ST1): goals, the activity credit, nutrients and the meal-estimate consent.
struct CaptureSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        CaptureSettingsForm(goals: environment.goals)
    }
}

/// The form of the settings; the goal editor lives here so that the sub page for the further goals edits the same plan.
private struct CaptureSettingsForm: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @State private var editor: GoalPlanEditor
    @State private var showsLookupConsent = false

    init(goals: GoalStore) {
        _editor = State(initialValue: GoalPlanEditor(goals: goals))
    }

    /// One write permission of Health: iOS reports it per type, so a refusal is shown instead of staying silent.
    @ViewBuilder
    private func writeRow(_ title: LocalizedStringKey, access: HealthWriteAccess?, connected: Bool,
                          request: @escaping () async -> Void) -> some View {
        switch access {
        case .allowed:
            LabeledContent(title) { Text("erlaubt").foregroundStyle(.secondaryText) }
        case .denied:
            LabeledContent(title) {
                Button("Nicht erlaubt · Health öffnen") {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                }
            }
        case .notAsked:
            LabeledContent(title) {
                if connected {
                    Button("Erlauben") { Task { await request() } }
                } else {
                    Text("noch nicht gefragt").foregroundStyle(.secondaryText)
                }
            }
        case .unavailable, nil:
            EmptyView()
        }
    }

    private func goal<Value>(_ keyPath: WritableKeyPath<GoalPlan, Value>) -> Binding<Value> {
        Binding(get: { editor.plan[keyPath: keyPath] }, set: { editor.set(keyPath, to: $0) })
    }

    var body: some View {
        @Bindable var settings = environment.settings
        let capture = environment.capture
        Form {
            Section {
                ValueStepper("Kalorien (Grundziel)", value: goal(\.kcal), in: GoalRanges.kcal, step: 50, unit: "kcal") {
                    IntakeFormat.kcal(Double($0), estimated: false)
                }
                ValueStepper("Wasser", value: goal(\.waterMilliliters), in: GoalRanges.waterMilliliters, step: 250,
                             kind: .decimal(fractionDigits: 2), scale: 1000, unit: "l") { IntakeFormat.liters($0) }
                ValueStepper("Training pro Woche", value: goal(\.workoutMinutesPerWeek), in: GoalRanges.workoutMinutesPerWeek, step: 15,
                             kind: .durationMinutes, display: workoutGoalText)
                ValueStepper("Schritte pro Tag", value: goal(\.stepsPerDay), in: GoalRanges.stepsPerDay, step: 500,
                             unit: "Schritte", display: stepGoalText)
                Toggle("Eiweiß-Ziel", isOn: optionalGoal(\.proteinGrams, start: 120))
                if let protein = editor.plan.proteinGrams {
                    ValueStepper("Eiweiß", value: goal(\.proteinGrams, orStart: protein), in: GoalRanges.proteinGrams, step: 5, unit: "g") {
                        IntakeFormat.grams(Double($0), estimated: false)
                    }
                }
                NavigationLink {
                    GoalPlanView(editor: editor)
                } label: {
                    Text("Weitere Ziele und frühere Stände")
                }
            } header: {
                Text("Ziele")
            } footer: {
                Text("Die Vorgaben sind Platzhalter, keine Empfehlung. Trag deine eigenen Ziele ein. Eine Änderung gilt ab heute; frühere Tage behalten ihr Ziel. Das Kalorienziel ist das Grundziel für einen Tag ohne angerechnete Aktivität. Zur Trainingszeit zählen Trainings aus Tagwerk und aus Health. Schritte liest Tagwerk aus Health; 0 blendet ein Ziel aus.")
            }

            Section {
                Picker("Aktivität anrechnen", selection: $settings.activityCreditPercent) {
                    ForEach(EnergyBudget.creditPercents, id: \.self) { percent in
                        Text(percent == 0 ? String(localized: "Aus") : "\(percent) %").tag(percent)
                    }
                }
                .accessibilityIdentifier("activityCredit")
            } header: {
                Text("Aktivität")
            } footer: {
                Text("Ein Teil der Aktivitätsenergie aus Health erhöht dein Tagesbudget. Geräte schätzen sie eher zu hoch, deshalb zählt voreingestellt die Hälfte. Das Kalorienziel gilt für einen Tag ohne angerechnete Aktivität.")
            }

            Section {
                LabeledContent("Aktive Energie lesen") {
                    if capture.activeEnergyAccess == .notAsked {
                        Button("Erlauben") { Task { await capture.allowActiveEnergy() } }
                            .accessibilityIdentifier(AccessibilityID.Capture.allowActiveEnergy)
                    } else if capture.activeEnergyAccess == .asked {
                        Text("Angefragt").foregroundStyle(.secondaryText)
                    }
                }
                writeRow("Gewicht schreiben", access: capture.weightWriteAccess, connected: capture.healthConnected) {
                    await capture.allowBodyAccess()
                }
                writeRow("Größe schreiben", access: capture.heightWriteAccess, connected: capture.healthConnected) {
                    await capture.allowHeightWriting()
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Hier steht, was Tagwerk in Health schreiben darf. „Nicht erlaubt“ ändert nur die Health-App, unter Profil › Apps › Tagwerk; solange es fehlt, bleibt der Eintrag in Tagwerk und wird nicht nach Health übertragen. Ob das Lesen erlaubt ist, zeigt iOS nicht an.")
            }

            Section {
                Toggle("Gesättigte Fettsäuren", isOn: $settings.saturatedFatEnabled)
                Toggle("Salz", isOn: $settings.saltEnabled)
                Toggle("Einträge anderer Apps mitzählen", isOn: Binding(
                    get: { settings.countsForeignNutrition },
                    set: { enabled in Task { await capture.setCountsForeignNutrition(enabled) } }))
                    .accessibilityIdentifier("countsForeignNutrition")
                LabeledContent("Weitere Nährwerte nach Health") {
                    if capture.furtherNutrientsAccess == .notAsked {
                        Button("Erlauben") { Task { await capture.allowFurtherNutrients() } }
                    } else {
                        Text("Angefragt").foregroundStyle(.secondaryText)
                    }
                }
            } header: {
                Text("Nährwerte")
            } footer: {
                Text("Ballaststoffe und Zucker sind immer dabei; gesättigte Fettsäuren und Salz erscheinen im Mahlzeitenblatt und in der Karte „Nährwerte“, wenn du sie einschaltest. Tagwerk liest für „Einträge anderer Apps mitzählen“ Ernährungseinträge aus Health, die nicht von Tagwerk stammen. iOS teilt Tagwerk nicht mit, ob du das Lesen erlaubt hast; ohne Erlaubnis sieht es so aus, als gäbe es keine fremden Einträge. Prüfen kannst du es in Health › Teilen › Apps › Tagwerk. Ob Health das Schreiben der weiteren Nährwerte erlaubt, steht an derselben Stelle.")
            }

            Section {
                Toggle("Körperfett erfassen", isOn: $settings.bodyFatEnabled)
                    .accessibilityIdentifier("bodyFatEnabled")
            } header: {
                Text("Gewicht")
            } footer: {
                Text("Tagwerk schreibt dein Gewicht nach Health und liest Messungen anderer Apps, zum Beispiel einer Waage. iOS teilt Tagwerk nicht mit, ob du das Lesen erlaubt hast; ohne Erlaubnis sieht es so aus, als gäbe es keine fremden Messungen. Prüfen kannst du es in Health › Teilen › Apps › Tagwerk. Der Körperfettanteil ist ein zweites Feld im Gewichtsblatt und eine zweite Linie im Verlauf.")
            }

            BodyProfileSection(store: environment.bodyProfile, heightWriteAccess: capture.heightWriteAccess)

            GoalPlanningSettingsSection()

            Section {
                ForEach(0..<DrinkPresets.defaults.count, id: \.self) { index in
                    ValueStepper("Portion \(index + 1)", value: presetBinding(index), in: DrinkPresets.range,
                                 step: DrinkPresets.step, unit: "ml") { "\($0) ml" }
                        .accessibilityIdentifier("drinkPreset\(index + 1)")
                }
                Button("Zurücksetzen") { settings.drinkPresets = DrinkPresets.defaults }
                    .accessibilityIdentifier("drinkPresetsReset")
            } header: {
                Text("Trinkportionen")
            } footer: {
                Text("Die drei Schnellknöpfe im Tab „Erfassen“ tragen diese Mengen ein, in dieser Reihenfolge.")
            }

            Section {
                Toggle("Mahlzeiten von ChatGPT schätzen", isOn: $settings.mealEstimationConsent)
                    .disabled(!environment.ai.isSignedIn)
            } header: {
                Text("Schätzung")
            } footer: {
                if environment.ai.isSignedIn {
                    Text("Zum Schätzen sendet Tagwerk nur Text und Foto der jeweiligen Mahlzeit an ChatGPT (OpenAI), zum Lesen eines Etiketts nur dessen Foto, und nur, wenn du auf „Schätzen“ tippst oder ein Foto für ein Etikett aufnimmst oder auswählst. Daten aus Health, Ziele und frühere Einträge werden nie gesendet. Ausgeschaltet trägst du Werte selbst ein.")
                } else {
                    Text("Melde dich unter Einstellungen › KI bei ChatGPT an, um Mahlzeiten schätzen zu lassen.")
                }
            }

            Section {
                Toggle("Online-Suche in Open Food Facts", isOn: Binding(
                    get: { settings.isFoodLookupEnabled },
                    set: { enabled in
                        // Switching on asks for the consent and the contact address again; switching off keeps the address.
                        if enabled { showsLookupConsent = true } else { settings.foodLookupConsent = false }
                    }))
                    .accessibilityIdentifier(AccessibilityID.FoodLookup.toggle)
                if settings.isFoodLookupEnabled {
                    FoodLookupContactField()
                }
                Link("Daten: Open Food Facts (ODbL)", destination: Self.openFoodFactsURL)
            } header: {
                Text("Online-Suche")
            } footer: {
                Text("Damit kannst du verpackte Lebensmittel in Open Food Facts nach Namen suchen, nur auf dein Tippen. Dabei gehen das Suchwort, deine IP-Adresse und die Kontaktadresse an den Betreiber, nie Mengen, Mahlzeiten, Ziele oder Daten aus Health. Ohne Kontaktadresse geht keine Anfrage hinaus; leerst du das Feld, schaltet sich die Suche aus. Die Datenbank steht unter der Open Database License (ODbL), ihre Inhalte unter der Database Contents License (DbCL). Die Daten stammen von Freiwilligen und können falsch sein. Produktbilder (CC BY-SA 3.0) lädt Tagwerk nicht. Ein übernommenes Produkt steht in „Meine Lebensmittel“ mit dem Hinweis auf die Quelle.")
            }

            Section {
                Toggle("In Planen anzeigen", isOn: $settings.showsIntakeInPlan)
                Toggle("Ernährung im Widget zeigen", isOn: $settings.widgetShowsNutrition)
            } header: {
                Text("Anzeige")
            } footer: {
                Text("„In Planen anzeigen“ zeigt Kalorien, Wasser und Schritte von heute unter dem Datum im Tab „Planen“, sobald du etwas erfasst hast. Ist „Ernährung im Widget zeigen“ aus, stehen die Werte und die Schritte nicht im Widget. Auf dem Sperrbildschirm erscheinen sie nie.")
            }
        }
        .navigationTitle("Erfassen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsLookupConsent) {
            FoodLookupConsentSheet {
                showsLookupConsent = false
            } onDecline: {
                showsLookupConsent = false
            }
        }
    }

    /// The home page of the data source named in the attribution.
    private static let openFoodFactsURL = URL(string: "https://world.openfoodfacts.org")!

    /// A goal that can be switched off (`nil`): the toggle sets `start` when it is switched on.
    private func optionalGoal(_ keyPath: WritableKeyPath<GoalPlan, Int?>, start: Int) -> Binding<Bool> {
        Binding(get: { editor.plan[keyPath: keyPath] != nil }, set: { editor.set(keyPath, to: $0 ? start : nil) })
    }

    /// The value of a goal that is switched on, as a plain number for the stepper.
    private func goal(_ keyPath: WritableKeyPath<GoalPlan, Int?>, orStart start: Int) -> Binding<Int> {
        Binding(get: { editor.plan[keyPath: keyPath] ?? start }, set: { editor.set(keyPath, to: $0) })
    }

    /// One portion of the quick buttons; every write goes through the rules, so the three values stay inside the range.
    private func presetBinding(_ index: Int) -> Binding<Int> {
        let settings = environment.settings
        return Binding(get: { settings.drinkPresets[index] },
                       set: { newValue in
                           var presets = settings.drinkPresets
                           presets[index] = newValue
                           settings.drinkPresets = presets
                       })
    }

    /// "2 h 30 min"; "aus" when the goal is off.
    private func workoutGoalText(_ minutes: Int) -> String {
        minutes > 0 ? IntakeFormat.duration(minutes: minutes) : String(localized: "aus")
    }

    /// "8.000"; "ohne Ziel" at 0.
    private func stepGoalText(_ steps: Int) -> String {
        steps > 0 ? IntakeFormat.grouped(steps) : String(localized: "ohne Ziel")
    }
}
