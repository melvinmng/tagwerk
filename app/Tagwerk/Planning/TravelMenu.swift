import SwiftUI
import TagwerkCore

/// Opens the sheet "Fahrzeit" of an event from the travel menu; set by the day view, `nil` where the menu is not offered
/// (the preview of a neighbour page).
private struct EditTravelKey: EnvironmentKey {
    // A closure is not Sendable; the value is only ever read and set on the main actor by SwiftUI.
    nonisolated(unsafe) static var defaultValue: ((CalendarEvent) -> Void)? = nil
}

extension EnvironmentValues {
    var editTravel: ((CalendarEvent) -> Void)? {
        get { self[EditTravelKey.self] }
        set { self[EditTravelKey.self] = newValue }
    }
}

/// What the menu on a travel block needs: the event the trip belongs to, the model and the action "Fahrzeit ändern …".
struct TravelMenuContext {
    let event: CalendarEvent
    let model: PlanningModel
    let onEdit: () -> Void
}

/// The menu of a travel block (PL11b): "Route in Karten", "Fahrzeit ändern …" and "Keine Fahrzeit für diesen Termin".
/// A tap opens it; the label is the block itself.
struct TravelMenu<LabelContent: View>: View {
    let segment: TravelSegment
    let transport: TravelTransport
    let context: TravelMenuContext
    /// The label holds only the capsule, so the menu says the overlap itself (a menu is one element for VoiceOver).
    var announcesOverlap = false
    @ViewBuilder let label: () -> LabelContent

    var body: some View {
        Menu {
            let places = context.model.travelPlaces(of: segment, event: context.event)
            Button {
                if let places { TravelRoute.open(from: places.from, to: places.to, transport: transport) }
            } label: {
                Label("Route in Karten", systemImage: "arrow.up.forward.app")
            }
            // Without a known end (no home address) there is no route to open.
            .disabled(places == nil)
            Button { context.onEdit() } label: {
                Label("Fahrzeit ändern …", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                // Only this occurrence, without the question for the series; the event sheet takes it back.
                Task { await context.model.setTravelOverride(.none, for: context.event, series: false) }
            } label: {
                Label("Keine Fahrzeit für diesen Termin", systemImage: "nosign")
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(announcesOverlap && segment.isTight
            ? TravelText.accessibilityLabel(segment, transport: transport) + ", " + TravelText.overlapAccessibility(minutes: segment.overlapMinutes)
            : TravelText.accessibilityLabel(segment, transport: transport))
        .accessibilityHint(String(localized: "Öffnet Aktionen zur Fahrzeit"))
    }
}

/// "Abbrechen" in the sheet "Fahrzeit": closes it without saving.
struct TravelSheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Abbrechen") { dismiss() }
    }
}
