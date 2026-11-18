import SwiftUI
import TagwerkCore

/// Water of the day (mockup E4a): single entries, another amount, time.
struct DrinkSheet: View {
    let model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 250
    @State private var time = Date()
    @State private var editing: DrinkValue?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Andere Menge: \(amount) ml", value: $amount, in: 50...2000, step: 50)
                    DatePicker("Zeit", selection: $time, displayedComponents: .hourAndMinute)
                    Button("Hinzufügen") {
                        let amount = amount
                        let date = dateOnDay(time)
                        Task { await model.addWater(amount, at: date) }
                        dismiss()
                    }
                } footer: {
                    Text("Die Knöpfe im Tab erfassen sofort. Getränke mit Kalorien trägst du unter „Essen“ ein.")
                }
                if !model.drinks.isEmpty {
                    Section {
                        ForEach(model.drinks) { drink in
                            Button { editing = drink } label: {
                                HStack {
                                    Text(CaptureText.time(drink.date, calendar: model.calendar))
                                    Spacer()
                                    Text("\(drink.milliliters) ml").monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                            .swipeActions {
                                Button(role: .destructive) { Task { await model.delete(drink.id) } } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("Wasser · \(IntakeFormat.liters(model.intake.waterMilliliters))")
                    } footer: {
                        Text("Wische einen Eintrag nach links, um ihn zu löschen.")
                    }
                }
            }
            .navigationTitle("Trinken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear { time = model.entryDate }
            .safeAreaInset(edge: .bottom) {
                // Deleting here must be undoable here; the tab's capsule is hidden behind this sheet.
                if let notice = model.undo, case .restore = notice.action {
                    UndoCapsule(title: notice.text, caption: "Gelöscht", symbol: "trash.circle.fill",
                                duration: HealthMirror.undoWindow,
                                onUndo: { Task { await model.undoLast() } },
                                onExpire: { model.clearUndo(notice) })
                        .id(notice.id)
                }
            }
            .sheet(item: $editing) { drink in
                DrinkEditSheet(drink: drink) { updated in Task { await model.updateDrink(updated) } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The chosen clock time on the shown day.
    private func dateOnDay(_ time: Date) -> Date {
        let calendar = model.calendar
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return model.day.startDate(in: calendar).addingTimeInterval(TimeInterval((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60))
    }
}

private struct DrinkEditSheet: View {
    @State var drink: DrinkValue
    let onSave: (DrinkValue) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Menge: \(drink.milliliters) ml", value: $drink.milliliters, in: 50...2000, step: 50)
                DatePicker("Zeit", selection: $drink.date, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Wasser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(drink)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
