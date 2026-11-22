import SwiftUI
import TagwerkCore

/// The page "Fahrzeit" of one event (PL13b, PL14c): "Automatisch" (Apple Maps, with the value that applies now), "Feste Dauer"
/// or "Keine". Only for "Automatisch" the transport and the start of the trip can be chosen as well.
/// The choice is a draft until "Sichern"; for a repeating event the question "Nur diesen Termin / Diesen und alle folgenden"
/// comes then. The dialog hangs on the form, not on a row.
struct TravelOverrideView: View {
    let event: CalendarEvent
    let model: PlanningModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var minutes: Int
    @State private var transport: TravelTransport?
    @State private var start: TravelStart?
    @State private var askingSeries = false
    /// What the plan shows for the event now: the value next to "Automatisch" and the rule that applies to the start.
    private let shown: TravelSegment?
    private let hasPreviousPlace: Bool

    private enum Mode: Hashable { case automatic, none, fixed }

    init(event: CalendarEvent, model: PlanningModel) {
        self.event = event
        self.model = model
        let current = model.travelChoice(for: event)
        let shown = model.days.lazy.compactMap { $0.travel.first { $0.eventID == event.id && $0.direction == .toEvent } }.first
        self.shown = shown
        hasPreviousPlace = model.hasPreviousPlace(before: event)
        switch current.mode {
        case .automatic: _mode = State(initialValue: .automatic)
        case .none: _mode = State(initialValue: .none)
        case .fixed: _mode = State(initialValue: .fixed)
        }
        _transport = State(initialValue: current.transport)
        _start = State(initialValue: current.start)
        // A fixed time starts from what the plan shows now, so "Feste Dauer" corrects a value instead of starting from zero.
        let startMinutes = current.mode.storedMinutes > 0 ? current.mode.storedMinutes : (shown?.minutes ?? TravelRules.defaultProvisionalMinutes)
        _minutes = State(initialValue: TravelOverrideRules.clampedFixedMinutes(startMinutes))
    }

    var body: some View {
        Form {
            Section {
                modeRow(String(localized: "Automatisch"), detail: shown.map(TravelText.valueText), selected: mode == .automatic) {
                    mode = .automatic
                }
                modeRow(String(localized: "Feste Dauer"), detail: nil, selected: mode == .fixed) { mode = .fixed }
                if mode == .fixed {
                    ValueStepper("Dauer", value: $minutes,
                                 in: TravelOverrideRules.minimumFixedMinutes...TravelOverrideRules.maximumFixedMinutes,
                                 step: TravelOverrideRules.stepMinutes, kind: .durationMinutes, unit: "min",
                                 display: CapacityText.duration)
                }
                modeRow(String(localized: "Keine"), detail: nil, selected: mode == .none) { mode = .none }
            } footer: {
                Text("Automatisch berechnet Apple Karten die Fahrzeit. „Keine“ und eine feste Dauer gelten nur in Tagwerk, auch ohne Netz, und haben Vorrang.")
            }
            if mode == .automatic {
                Section {
                    optionRow(TravelText.transportRule(model.settings.travelTransport), selected: transport == nil) { transport = nil }
                    ForEach(TravelTransport.allCases, id: \.self) { option in
                        optionRow(TravelText.name(option), symbol: TravelText.symbol(option), selected: transport == option) {
                            transport = option
                        }
                    }
                } header: {
                    Text("Verkehrsmittel")
                }
                Section {
                    optionRow(TravelText.startRule(shown?.origin ?? .home), selected: start == nil) { start = nil }
                    optionRow(String(localized: "Zuhause"), selected: start == .home) { start = .home }
                    optionRow(String(localized: "Vorheriger Termin"), selected: start == .previousEvent,
                              isEnabled: hasPreviousPlace || start == .previousEvent) { start = .previousEvent }
                } header: {
                    Text("Start")
                }
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

    /// A row of the first section: the title, what applies now (if any) and a tick on the chosen one.
    private func modeRow(_ title: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let detail { Text(detail).foregroundStyle(.secondaryText) }
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionRow(_ title: String, symbol: String? = nil, selected: Bool, isEnabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let symbol { Label(title, systemImage: symbol).foregroundStyle(.primary) } else { Text(title).foregroundStyle(.primary) }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .disabled(!isEnabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var choice: TravelChoice {
        switch mode {
        case .automatic: TravelChoice(transport: transport, start: start)
        case .none: TravelChoice(mode: .none)
        case .fixed: TravelChoice(mode: .fixed(minutes: minutes))
        }
    }

    private func save() {
        if event.isRecurring { askingSeries = true } else { apply(series: false) }
    }

    private func apply(series: Bool) {
        let chosen = choice
        Task {
            await model.setTravelChoice(chosen, for: event, series: series)
            dismiss()
        }
    }
}
