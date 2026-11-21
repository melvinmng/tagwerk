import SwiftUI
import TagwerkCore

/// Page for one new reminder: a distance before ("2 Stunden vorher") or a time of day some days before ("1 Tag vorher um 18:00").
struct ReminderOffsetPicker: View {
    let isAllDay: Bool
    let subject: ReminderSubject
    var calendar: Calendar = .tagwerk
    let onAdd: (ReminderOffset) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable { case before, atTime }

    @State private var mode: Mode = .before
    @State private var amount = 1
    @State private var unit: ReminderUnit
    @State private var daysBefore = 1
    @State private var time: Date

    init(isAllDay: Bool, subject: ReminderSubject, calendar: Calendar = .tagwerk, onAdd: @escaping (ReminderOffset) -> Void) {
        self.isAllDay = isAllDay
        self.subject = subject
        self.calendar = calendar
        self.onAdd = onAdd
        _unit = State(initialValue: isAllDay ? .days : .hours)
        _time = State(initialValue: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_700_000_000)) ?? .now)
    }

    var body: some View {
        Form {
            Section {
                Picker("Art", selection: $mode.animation()) {
                    Text("Vorher").tag(Mode.before)
                    Text("Zu einer Uhrzeit").tag(Mode.atTime)
                }
                .pickerStyle(.segmented)
                switch mode {
                case .before:
                    ValueStepper("Menge", value: $amount, in: 0...ReminderOffset.maximumAmount) { "\($0)" }
                    Picker("Einheit", selection: $unit) {
                        ForEach(units, id: \.self) { Text(Self.name(of: $0)).tag($0) }
                    }
                case .atTime:
                    ValueStepper("Tage vorher", value: $daysBefore, in: 0...ReminderOffset.maximumDaysBefore) { "\($0)" }
                    DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.calendar, calendar)
                        .environment(\.timeZone, calendar.timeZone)
                }
            }
            Section("Vorschau") {
                Text(preview)
            }
            Section("Schnellauswahl") {
                ForEach(quickChoices, id: \.self) { choice in
                    Button(ReminderText.describe(choice, subject: subject, isAllDay: isAllDay, locale: .current, calendar: calendar)) { select(choice) }
                }
            }
        }
        .navigationTitle("Erinnerung hinzufügen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Hinzufügen") {
                    onAdd(offset)
                    dismiss()
                }
            }
        }
    }

    private var units: [ReminderUnit] { ReminderUnit.allCases.filter { !isAllDay || !$0.needsTimeOfDay } }

    /// The reminder the controls describe.
    private var offset: ReminderOffset {
        switch mode {
        case .before:
            return .before(amount: amount, unit: unit)
        case .atTime:
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            return .at(daysBefore: daysBefore, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
    }

    private var preview: String { ReminderText.describe(offset, subject: subject, isAllDay: isAllDay, locale: .current, calendar: calendar) }

    private var quickChoices: [ReminderOffset] {
        var choices: [ReminderOffset] = [.before(amount: 0, unit: isAllDay ? .days : .minutes)]
        if !isAllDay { choices.append(.before(amount: 1, unit: .hours)) }
        return choices + [.before(amount: 1, unit: .days), .before(amount: 1, unit: .weeks)]
    }

    private func select(_ choice: ReminderOffset) {
        guard case .before(let newAmount, let newUnit) = choice else { return }
        mode = .before
        amount = newAmount
        unit = newUnit
    }

    static func name(of unit: ReminderUnit) -> LocalizedStringKey {
        switch unit {
        case .minutes: "Minuten"
        case .hours: "Stunden"
        case .days: "Tage"
        case .weeks: "Wochen"
        }
    }
}
