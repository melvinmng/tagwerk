import SwiftUI
import TagwerkCore

/// Enters or edits a body weight (decision KG1c): the last value is filled in, the step is 0.1 kg, the time can be changed, and
/// the body fat is a second field that the settings switch on (decision KG4b).
struct WeightSheet: View {
    let model: CaptureModel
    /// The entry that is edited; `nil` for a new one.
    let existing: WeightValue?
    /// Called after the entry was saved (the morning start refreshes its row).
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var kilograms: Double
    @State private var date: Date
    @State private var tracksBodyFat: Bool
    @State private var bodyFat: Double
    /// The value the sheet started with, so a late suggestion from Health never replaces something the user already typed.
    private let prefilled: Double

    init(model: CaptureModel, existing: WeightValue?, onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.existing = existing
        self.onSaved = onSaved
        let latest = model.weights.latestOwn()
        let start = existing?.kilograms ?? latest?.kilograms ?? WeightRules.startKilograms
        prefilled = start
        _kilograms = State(initialValue: start)
        _date = State(initialValue: existing?.date ?? model.weightEntryDate)
        _tracksBodyFat = State(initialValue: existing?.bodyFatPercent != nil)
        _bodyFat = State(initialValue: existing?.bodyFatPercent ?? latest?.bodyFatPercent ?? 20)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ValueStepper("Gewicht", value: $kilograms, in: WeightRules.minimumKilograms...WeightRules.maximumKilograms,
                                 step: WeightRules.stepKilograms, kind: .decimal(fractionDigits: 1), unit: "kg") {
                        WeightFormat.kilograms($0)
                    }
                    .accessibilityIdentifier(AccessibilityID.Capture.weightField)
                    DatePicker("Zeitpunkt", selection: $date, in: ...Date.now.addingTimeInterval(60),
                               displayedComponents: [.date, .hourAndMinute])
                    if model.settings.bodyFatEnabled {
                        Toggle("Körperfett", isOn: $tracksBodyFat)
                        if tracksBodyFat {
                            ValueStepper("Körperfettanteil", value: $bodyFat, in: WeightRules.minimumBodyFatPercent...WeightRules.maximumBodyFatPercent,
                                         step: WeightRules.stepBodyFatPercent, kind: .decimal(fractionDigits: 1), unit: "%") {
                                WeightFormat.bodyFat($0)
                            }
                        }
                    }
                } footer: {
                    Text("Für den Verlauf zählt die früheste Messung des Tages. Weitere Messungen am selben Tag bleiben in der Liste.")
                }
            }
            .navigationTitle("Gewicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).accessibilityIdentifier(AccessibilityID.Capture.weightSave)
                }
            }
            .task {
                // Without an own weight yet, a measurement of another app (a scale) is the better starting point than a fixed value.
                guard existing == nil, model.weights.latestOwn() == nil, kilograms == prefilled,
                      let known = await model.latestKnownKilograms() else { return }
                if kilograms == prefilled { kilograms = known }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        // With the switch off the field is not shown, so an edit keeps the body fat the entry already has.
        let fat: Double? = model.settings.bodyFatEnabled ? (tracksBodyFat ? WeightRules.clampedBodyFat(bodyFat) : nil)
                                                         : existing?.bodyFatPercent
        let value = WeightValue(id: existing?.id ?? UUID(), date: date, kilograms: WeightRules.clamped(kilograms), bodyFatPercent: fat)
        let isNew = existing == nil
        Task {
            await model.saveWeight(value, isNew: isNew)
            onSaved()
        }
        dismiss()
    }
}
