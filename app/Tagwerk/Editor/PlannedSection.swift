import SwiftUI
import TagwerkCore

/// "Geplant" in the task editor (mockup C4): working day, time blocks with start and length, delete and add.
/// Recurring reminders get a separate card for Tagwerk's own values (mockup G4).
struct PlannedSection: View {
    @Binding var edit: PlannedEdit
    let calendar: Calendar
    let isRecurring: Bool
    let onShowDay: ((PlanDay) -> Void)?

    var body: some View {
        if isRecurring {
            Section {
                LabeledContent("Titel, Fälligkeit, Wiederholung", value: "alle Tage")
            } header: {
                Text("Erinnerung")
            } footer: {
                Text("Änderungen oben gelten immer für die ganze Serie; Erinnerungen kennen keine Ausnahme für einen Tag.")
            }
            Section {
                EstimateField(minutes: $edit.recurringMinutes)
                Picker("Gilt für", selection: $edit.recurringForAll) {
                    Text("Nur heute").tag(false)
                    Text("Alle ab heute").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("In Tagwerk · Aufwand")
            } footer: {
                Text("Reservierte Zeit an jedem Tag der Serie. „Alle ab heute“ ändert den Aufwand für heute und alle folgenden Tage.")
            }
        }

        Section {
            Toggle("Arbeitstag", isOn: hasDay)
            if let day = edit.day {
                DatePicker("Tag", selection: dayDate, displayedComponents: .date)
                    .environment(\.calendar, calendar)
                if let onShowDay {
                    Button("Zum Tag in „Planen“ ›") { onShowDay(day) }
                }
                if edit.day != edit.originalDay, edit.blocks.contains(where: { !$0.isDeleted }) {
                    Toggle("Zeitblöcke mitverschieben", isOn: $edit.moveBlocks)
                }
            }
            ForEach($edit.blocks) { $block in
                if !block.isDeleted {
                    DatePicker("Zeitblock", selection: $block.start, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.calendar, calendar)
                    Stepper("Dauer: \(CapacityText.duration(block.minutes))", value: $block.minutes, in: 15...720, step: 15)
                    Button("Zeitblock löschen", role: .destructive) { block.isDeleted = true }
                }
            }
            ForEach($edit.newBlocks) { $block in
                DatePicker("Neuer Zeitblock", selection: $block.start, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.calendar, calendar)
                Stepper("Dauer: \(CapacityText.duration(block.minutes))", value: $block.minutes, in: 15...720, step: 15)
            }
            Button("Zeitblock hinzufügen") {
                let day = edit.day ?? PlanDay(date: .now, calendar: calendar)
                let start = day.startDate(in: calendar).addingTimeInterval(9 * 3600)
                edit.newBlocks.append(PlannedEdit.NewBlock(start: start, minutes: 60))
            }
        } header: {
            Text("Geplant")
        } footer: {
            Text("Gilt mit „Sichern“. Der Arbeitstag ändert nur die Planung in Tagwerk, nicht die Fälligkeit.")
        }
    }

    private var hasDay: Binding<Bool> {
        Binding(get: { edit.day != nil },
                set: { edit.day = $0 ? (edit.originalDay ?? PlanDay(date: .now, calendar: calendar)) : nil })
    }

    private var dayDate: Binding<Date> {
        Binding(get: { (edit.day ?? PlanDay(date: .now, calendar: calendar)).startDate(in: calendar) },
                set: { edit.day = PlanDay(date: $0, calendar: calendar) })
    }
}
