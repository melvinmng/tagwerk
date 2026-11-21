import SwiftUI
import TagwerkCore

/// Sets the travel time of one event by hand (F2): "Automatisch" (Apple Maps), "Keine" or a fixed time in 5-minute steps.
/// The choice is a draft until "Sichern"; for a repeating event the question "Nur diesen Termin / Diesen und alle
/// folgenden" comes then. The dialog hangs on the form, not on a row.
struct TravelOverrideView: View {
    let event: CalendarEvent
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice
    @State private var minutes: Int
    @State private var askingSeries = false

    private enum Choice: Hashable { case automatic, none, fixed }

    init(event: CalendarEvent, model: PlanningModel) {
        self.event = event
        self.model = model
        let current = model.travelOverrideMode(for: event)
        let shown = model.days.lazy.compactMap { $0.travel.first { $0.eventID == event.id && $0.direction == .toEvent } }.first
        switch current {
        case .automatic: _choice = State(initialValue: .automatic)
        case .none: _choice = State(initialValue: .none)
        case .fixed: _choice = State(initialValue: .fixed)
        }
        // A fixed time starts from what the plan shows now, so "Feste Zeit" corrects a value instead of starting from zero.
        let start = current.storedMinutes > 0 ? current.storedMinutes : (shown?.minutes ?? TravelRules.defaultProvisionalMinutes)
        _minutes = State(initialValue: TravelOverrideRules.clampedFixedMinutes(start))
    }

    var body: some View {
        Form {
            Section {
                Picker("Fahrzeit", selection: $choice) {
                    Text("Automatisch").tag(Choice.automatic)
                    Text("Keine").tag(Choice.none)
                    Text("Feste Zeit").tag(Choice.fixed)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if choice == .fixed {
                    ValueStepper("Dauer", value: $minutes,
                                 in: TravelOverrideRules.minimumFixedMinutes...TravelOverrideRules.maximumFixedMinutes,
                                 step: TravelOverrideRules.stepMinutes, kind: .durationMinutes, unit: "min",
                                 display: CapacityText.duration)
                }
            } footer: {
                Text("Automatisch berechnet Apple Karten die Fahrzeit. „Keine“ und eine feste Zeit gelten nur in Tagwerk, auch ohne Netz, und haben Vorrang.")
            }
        }
        .navigationTitle("Fahrzeit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() } } }
        .confirmationDialog("Dieser Termin wiederholt sich", isPresented: $askingSeries, titleVisibility: .visible) {
            Button("Nur diesen Termin") { apply(series: false) }
            Button("Diesen und alle folgenden") { apply(series: true) }
        }
    }

    private var mode: TravelOverrideMode {
        switch choice {
        case .automatic: .automatic
        case .none: .none
        case .fixed: .fixed(minutes: minutes)
        }
    }

    private func save() {
        if event.isRecurring { askingSeries = true } else { apply(series: false) }
    }

    private func apply(series: Bool) {
        let chosen = mode
        Task {
            await model.setTravelOverride(chosen, for: event, series: series)
            dismiss()
        }
    }
}
