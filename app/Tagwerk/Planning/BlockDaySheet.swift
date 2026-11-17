import SwiftUI
import TagwerkCore

/// Picks another day for a block; time of day and length stay.
struct BlockDaySheet: View {
    let block: CalendarEvent
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(block: CalendarEvent, model: PlanningModel) {
        self.block = block
        self.model = model
        _date = State(initialValue: block.start)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Tag", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, model.calendar)
                .padding()
                .navigationTitle("Auf anderen Tag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verschieben") {
                            let oldDay = PlanDay(date: block.start, calendar: model.calendar)
                            let start = Int(block.start.timeIntervalSince(oldDay.startDate(in: model.calendar)) / 60)
                            Task { await model.moveBlock(block, toStartMinutes: start, on: PlanDay(date: date, calendar: model.calendar)) }
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
