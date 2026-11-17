import SwiftUI
import TagwerkCore

/// Date picker for "Datum wählen …" when moving a task.
struct RescheduleDateSheet: View {
    let item: TaskItem
    let calendar: Calendar
    let onPick: (DueDate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(item: TaskItem, calendar: Calendar, now: Date, onPick: @escaping (DueDate) -> Void) {
        self.item = item
        self.calendar = calendar
        self.onPick = onPick
        _date = State(initialValue: item.due?.startDate(in: calendar) ?? now)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Datum", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, calendar)
                .padding()
                .navigationTitle("Verschieben")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            onPick(DueDate(date: date, includeTime: false, calendar: calendar))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
