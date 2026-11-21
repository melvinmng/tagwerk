import SwiftUI
import TagwerkCore

/// The capsule "10 min zu früh" of a trip that starts before the previous event ends (PL10b): black on `travelWarningFill`,
/// bold caption2. It is an element of its own for VoiceOver and for the accessibility audit.
struct TravelWarningCapsule: View {
    let minutes: Int

    var body: some View {
        Text(TravelText.overlapText(minutes: minutes))
            .font(.caption2.weight(.bold)).foregroundStyle(.onTravelWarning)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.travelWarningFill, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TravelText.overlapAccessibility(minutes: minutes))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(AccessibilityID.Travel.warningCapsule)
    }
}

/// The travel time as an attachment to its event in the hour grid (PL8b): a lighter area in the colour of the event, flush
/// above it (the way home: flush below), with the departure and the minutes ("Los 15:05 · 25 min"). The capsule with the
/// overlap sits on the right; when the width does not suffice, the text gets shorter first and then only the capsule is left.
struct TravelSegmentView: View {
    let segment: TravelSegment
    let transport: TravelTransport
    /// The colour of the event the trip belongs to.
    let color: Color
    /// The time the trip starts ("15:05").
    let departure: String

    var body: some View {
        let isReturn = segment.direction == .returnHome
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: isReturn ? 0 : 7, bottomLeadingRadius: isReturn ? 7 : 0,
                                   bottomTrailingRadius: isReturn ? 7 : 0, topTrailingRadius: isReturn ? 0 : 7)
                .fill(color.opacity(0.12))
            content
                .padding(.horizontal, 5).padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
    }

    private func label(_ title: String) -> some View {
        Label(title, systemImage: TravelText.symbol(transport))
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon).lineLimit(1).fixedSize()
            .accessibilityLabel(TravelText.accessibilityLabel(segment, transport: transport))
    }

    private func option(_ title: String?) -> some View {
        HStack(spacing: 4) {
            if let title { label(title) }
            if segment.isTight {
                Spacer(minLength: 2)
                TravelWarningCapsule(minutes: segment.overlapMinutes)
            }
        }
    }

    /// The text candidates longest first, each with the capsule; then only the capsule; for a trip without overlap the
    /// shortest text repeats, so `ViewThatFits` always has four options.
    @ViewBuilder
    private var content: some View {
        let candidates = TravelText.gridCandidates(segment, departure: departure)
        let first = candidates[0], second = candidates[min(1, candidates.count - 1)], third = candidates[candidates.count - 1]
        ViewThatFits(in: .horizontal) {
            option(first)
            option(second)
            option(third)
            option(segment.isTight ? nil : third)
        }
    }
}

/// The travel time as a row in the list mode (PL9b): "Losfahren · 25 min ab Zuhause" with the capsule behind it.
struct TravelRow: View {
    let segment: TravelSegment
    let transport: TravelTransport
    let time: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                .accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.6)).frame(width: 4)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { title; capsule }
                VStack(alignment: .leading, spacing: 4) { title; capsule }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        Label(TravelText.rowText(segment), systemImage: TravelText.symbol(transport))
            .font(.subheadline).foregroundStyle(.secondary)
            .accessibilityLabel(TravelText.accessibilityLabel(segment, transport: transport))
    }

    @ViewBuilder
    private var capsule: some View {
        if segment.isTight { TravelWarningCapsule(minutes: segment.overlapMinutes) }
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
