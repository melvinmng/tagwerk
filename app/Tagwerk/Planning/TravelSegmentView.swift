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

/// One line under "Ort" in the entry sheet: "Fahrzeit · 25 min mit dem Auto ab Zuhause"; nothing without a value.
struct TravelInfoRow: View {
    let eventID: String
    let model: PlanningModel

    var body: some View {
        if let segment = model.days.lazy.compactMap({ $0.travel.first { $0.eventID == eventID } }).first {
            Label(TravelText.entryText(segment, transport: model.settings.travelTransport),
                  systemImage: TravelText.symbol(model.settings.travelTransport))
                .foregroundStyle(segment.isTight ? Color.orange : Color.secondary)
        }
    }
}
