import SwiftUI
import TagwerkCore

/// The travel time before an event in the hour grid: a grey hatched block over the width of the event's column,
/// with the transport symbol and the minutes; orange with "knapp" when it starts before the previous event ends.
struct TravelSegmentView: View {
    let segment: TravelSegment
    let transport: TravelTransport

    var body: some View {
        let color: Color = segment.isTight ? .orange : .gray
        ZStack(alignment: .topLeading) {
            Rectangle().fill(color.opacity(0.14))
            Canvas { context, size in
                var path = Path()
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 7
                }
                context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 1)
            }
            Label(TravelText.gridText(segment), systemImage: TravelText.symbol(transport))
                .font(.caption2.weight(.semibold)).foregroundStyle(segment.isTight ? Color.orange : Color.secondary)
                .labelStyle(.titleAndIcon).lineLimit(1)
                .padding(.horizontal, 5).padding(.top, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TravelText.accessibilityLabel(segment, transport: transport))
    }
}

/// The travel time as a row in the list mode; no action.
struct TravelRow: View {
    let segment: TravelSegment
    let transport: TravelTransport
    let time: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(segment.isTight ? Color.orange : Color.gray.opacity(0.6)).frame(width: 4)
            Label(TravelText.rowText(segment), systemImage: TravelText.symbol(transport))
                .font(.subheadline).foregroundStyle(segment.isTight ? Color.orange : Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TravelText.accessibilityLabel(segment, transport: transport))
    }
}

/// One row under "Ort" in the entry sheet: "Fahrzeit" with what applies now ("25 min mit dem Auto ab Zuhause", "~30 min ·
/// geschätzt", "Keine", "25 min · manuell"). It opens `TravelOverrideView`, where the time can be set by hand. Shown for
/// timed events while the setting "Fahrzeit berücksichtigen" is on.
struct TravelInfoRow: View {
    let event: CalendarEvent
    let model: PlanningModel

    var body: some View {
        if model.settings.travelTimeEnabled, !event.isAllDay {
            let transport = model.settings.travelTransport
            let segment = model.days.lazy.compactMap { $0.travel.first { $0.eventID == event.id && $0.direction == .toEvent } }.first
            NavigationLink {
                TravelOverrideView(event: event, model: model)
            } label: {
                LabeledContent {
                    Text(TravelText.overrideSummary(model.travelOverrideMode(for: event), segment: segment, transport: transport))
                        .foregroundStyle(segment?.isTight == true ? Color.orange : Color.secondary)
                } label: {
                    Label("Fahrzeit", systemImage: TravelText.symbol(transport))
                }
            }
        }
    }
}
