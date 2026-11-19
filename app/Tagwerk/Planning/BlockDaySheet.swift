import SwiftUI
import TagwerkCore

/// Picks another day for a block; time of day and length stay.
struct BlockDaySheet: View {
    let block: CalendarEvent
    let model: PlanningModel
    /// Called after "Verschieben": the block left the day, so the sheet that showed it closes too.
    var onMoved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(block: CalendarEvent, model: PlanningModel, onMoved: @escaping () -> Void = {}) {
        self.block = block
        self.model = model
        self.onMoved = onMoved
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
                            onMoved()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
