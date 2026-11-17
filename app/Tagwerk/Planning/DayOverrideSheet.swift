import SwiftUI
import TagwerkCore

/// Different working hours for one date, or a day off (design §11.2).
struct DayOverrideSheet: View {
    let day: PlanDay
    let calendar: Calendar
    let current: WorkHours?
    let onSave: (DayOverride?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isOff: Bool
    @State private var start: Date
    @State private var end: Date

    init(day: PlanDay, calendar: Calendar, current: WorkHours?, onSave: @escaping (DayOverride?) -> Void) {
        self.day = day
        self.calendar = calendar
        self.current = current
        self.onSave = onSave
        let base = day.startDate(in: calendar)
        let hours = current ?? WorkHours(startMinutes: 540, endMinutes: 1080)
        _isOff = State(initialValue: current == nil)
        _start = State(initialValue: base.addingTimeInterval(TimeInterval(hours.startMinutes * 60)))
        _end = State(initialValue: base.addingTimeInterval(TimeInterval(hours.endMinutes * 60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Freier Tag", isOn: $isOff)
                if !isOff {
                    DatePicker("Beginn", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ende", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section {
                    Button("Auf Wochenplan zurücksetzen") {
                        onSave(nil)
                        dismiss()
                    }
                }
            }
            .environment(\.calendar, calendar)
            .navigationTitle("Arbeitszeit an diesem Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(isOff ? .off : .hours(WorkHours(startMinutes: minutes(start), endMinutes: minutes(end))))
                        dismiss()
                    }
                    .disabled(!isOff && minutes(end) <= minutes(start))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func minutes(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Time and duration for a new block in the plan calendar.
struct BlockSheet: View {
    let task: TaskItem
    let day: PlanDay
    let calendar: Calendar
    let onCreate: (Date, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var minutes: Int?

    init(task: TaskItem, day: PlanDay, calendar: Calendar, onCreate: @escaping (Date, Int) -> Void) {
        self.task = task
        self.day = day
        self.calendar = calendar
        self.onCreate = onCreate
        _start = State(initialValue: day.startDate(in: calendar).addingTimeInterval(9 * 3600))
        _minutes = State(initialValue: task.estimateMinutes ?? 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(task.title).font(.headline)
                DatePicker("Beginn", selection: $start, displayedComponents: .hourAndMinute)
                EstimateField(minutes: $minutes)
            }
            .environment(\.calendar, calendar)
            .navigationTitle("Zeitblock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("In Kalender") {
                        onCreate(start, minutes ?? 60)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
