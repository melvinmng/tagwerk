import SwiftUI
import TagwerkCore

/// Effort of a recurring reminder (mockup g-A): "Nur dieser Tag" or "Alle" from this day on.
struct RecurringEffortSheet: View {
    let item: RecurringItem
    let day: PlanDay
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int?
    @State private var forAll = false

    init(item: RecurringItem, day: PlanDay, model: PlanningModel) {
        self.item = item
        self.day = day
        self.model = model
        _minutes = State(initialValue: item.minutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(item.title).font(.headline) }
                EstimateField(minutes: $minutes)
                Section {
                    Picker("Gilt für", selection: $forAll) {
                        Text("Nur dieser Tag").tag(false)
                        Text("Alle ab diesem Tag").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(effectText)
                }
            }
            .navigationTitle("Aufwand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            await model.setRecurringEffort(minutes, reminderID: item.reminderID, day: day, forAll: forAll)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var effectText: String {
        let date = day.startDate(in: model.calendar).formatted(.dateTime.weekday(.wide).day().month(.wide))
        let new = minutes.map(CapacityText.duration) ?? "kein Aufwand"
        return forAll
            ? "Ab \(date): \(new) statt \(CapacityText.duration(item.minutes)). Frühere Tage behalten ihren Wert."
            : "Nur am \(date): \(new) statt \(CapacityText.duration(item.minutes))."
    }
}
