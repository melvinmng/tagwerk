import SwiftUI
import TagwerkCore

/// A manual workout (mockup E5a): type, duration, start, optional calories.
struct WorkoutSheet: View {
    let model: CaptureModel
    let existing: WorkoutValue?
    /// Values from Siri ("Training erfassen"); the user still confirms with "Sichern".
    var initialActivity: WorkoutActivity? = nil
    var initialMinutes: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var activity: WorkoutActivity = .strength
    @State private var minutes = 45
    @State private var start = Date()
    @State private var kilocaloriesText = ""
    @State private var prepared = false
    @State private var workoutID = UUID().uuidString
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $activity) {
                        ForEach(WorkoutActivity.allCases, id: \.self) { activity in
                            Label(activity.displayName, systemImage: activity.symbolName).tag(activity)
                        }
                    }
                    .pickerStyle(.menu)
                    Stepper("Dauer: \(minutes) min", value: $minutes, in: 5...300, step: 5)
                    DatePicker("Beginn", selection: $start, in: ...Date())
                    HStack {
                        Text("Kalorien (optional)")
                        Spacer()
                        TextField("–", text: $kilocaloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Der Beginn ist so vorbelegt, dass das Training jetzt endet. Tagwerk schätzt keinen Verbrauch; ein leeres Feld bleibt leer.")
                }
                if let warning = model.overlapWarning(start: start, minutes: minutes) {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
                if let existing, let id = UUID(uuidString: existing.id) {
                    Section {
                        Button("Training löschen", role: .destructive) {
                            Task {
                                await model.delete(id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard !saving else { return }
                        saving = true
                        let workout = makeWorkout()
                        let isNew = existing == nil
                        Task { await model.saveWorkout(workout, isNew: isNew) }
                        dismiss()
                    }
                    .disabled(saving)
                }
            }
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let existing {
            workoutID = existing.id
            activity = existing.activity
            minutes = existing.minutes
            start = existing.start
            kilocaloriesText = existing.kilocalories.map { String(Int($0.rounded())) } ?? ""
        } else {
            let defaults = model.workoutDefaults
            activity = initialActivity ?? defaults.activity
            minutes = initialMinutes ?? defaults.minutes
            start = model.entryDate.addingTimeInterval(TimeInterval(-minutes * 60))
        }
    }

    /// The ID is fixed per sheet, so a second tap can never create a second workout.
    private func makeWorkout() -> WorkoutValue {
        let kilocalories = Double(kilocaloriesText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        return WorkoutValue(id: workoutID, activity: activity, start: start, minutes: minutes,
                            kilocalories: kilocalories, sourceName: nil, isOwn: true)
    }
}
