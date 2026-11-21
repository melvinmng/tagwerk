import SwiftUI
import TagwerkCore

/// "Schätzung und Ist" in the weekly review (FO14b): how long tasks took against their estimate, per source and per label,
/// as bars around "wie geschätzt", from the last eight weeks up to the shown week. Measured from time blocks plus focus
/// time outside them; stays on the iPhone.
struct EffortReviewSection: View {
    @Environment(AppEnvironment.self) private var environment
    let model: WeekReviewModel

    var body: some View {
        let data = reviewData
        Section {
            if data.groups.isEmpty {
                Text("Noch zu wenige Messungen.").foregroundStyle(.secondary)
            } else {
                EffortScaleRow()
            }
            // Sources first, the labels indented below them.
            ForEach(Array(data.sources.enumerated()), id: \.offset) { _, group in
                EffortGroupRow(group: group, isIndented: false)
            }
            ForEach(Array(data.labels.enumerated()), id: \.offset) { _, group in
                EffortGroupRow(group: group, isIndented: true)
            }
            if data.withoutEstimate > 0 {
                LabeledContent("Ohne Schätzung gemessen", value: "\(data.withoutEstimate)")
            }
            LabeledContent("Fokus in dieser Woche", value: CapacityText.duration(data.focusMinutes))
            LabeledContent("Messungen in dieser Woche", value: "\(data.samplesThisWeek)")
        } header: {
            Text("Schätzung und Ist · letzte 8 Wochen")
        } footer: {
            Text("Gemessen über Zeitblöcke; Fokus-Timer zählt nur außerhalb der Blöcke, letzte 8 Wochen.")
        }
    }

    private struct ReviewData {
        var groups: [EffortGroup]
        var withoutEstimate: Int
        var focusMinutes: Int
        var samplesThisWeek: Int

        var sources: [EffortGroup] { groups.filter { if case .source = $0.kind { true } else { false } } }
        var labels: [EffortGroup] { groups.filter { if case .label = $0.kind { true } else { false } } }
    }

    private var reviewData: ReviewData {
        let calendar = model.calendar
        let week = DateInterval(start: model.weekStart.startDate(in: calendar),
                                end: model.weekStart.adding(days: 7, calendar: calendar).startDate(in: calendar))
        // For the current week the window ends now, for an earlier one at the end of that week.
        let end = min(week.end, Date.now)
        let samples = environment.effort.samples(until: end)
        let groups = EffortStats.groups(samples, now: end).filter { group in
            if case .label = group.kind { return group.medianRatio != nil }
            return true
        }
        let focusSeconds = environment.focusStore.finishedSessions(in: week).reduce(0) { $0 + $1.focusedSeconds }
        return ReviewData(groups: groups, withoutEstimate: EffortStats.withoutEstimate(samples, now: end),
                          focusMinutes: focusSeconds / 60,
                          samplesThisWeek: samples.filter { week.contains($0.completedAt) }.count)
    }
}

/// The scale of the bars: "−50 %", "wie geschätzt" at a third of the width, "+100 %".
private struct EffortScaleRow: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Text(EffortReviewText.deviationLabel(EffortReviewText.scale.lowerBound))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("wie geschätzt")
                    .position(x: proxy.size.width * EffortReviewText.position(deviationPercent: 0), y: proxy.size.height / 2)
                Text(EffortReviewText.deviationLabel(EffortReviewText.scale.upperBound))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// One group: its name and value, the bar and the number of tasks below; grey without a bar below the minimum.
private struct EffortGroupRow: View {
    let group: EffortGroup
    let isIndented: Bool

    private var name: String { EffortReviewText.name(of: group.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(isIndented ? "↳ \(name)" : name)
                Spacer(minLength: 8)
                if let deviation = group.deviationPercent {
                    Text(EffortReviewText.deviationLabel(deviation)).monospacedDigit().fontWeight(.semibold)
                } else {
                    Text(EffortReviewText.pendingLabel(count: group.count)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let deviation = group.deviationPercent {
                EffortDeviationBar(deviationPercent: deviation)
                    .frame(height: 12)
                    .accessibilityHidden(true)
            }
            Text(EffortReviewText.count(group.count)).font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(group.deviationPercent == nil ? Color.secondary : Color.primary)
        .padding(.leading, isIndented ? 16 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name) · \(EffortReviewText.count(group.count))"))
        .accessibilityValue(Text(EffortReviewText.detail(of: group)))
    }
}

/// A bar from "wie geschätzt" to the deviation: orange to the right (longer), blue to the left (shorter), with an
/// arrowhead when the value lies beyond the scale.
private struct EffortDeviationBar: View {
    let deviationPercent: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centre = width * EffortReviewText.position(deviationPercent: 0)
            let end = width * EffortReviewText.position(deviationPercent: deviationPercent)
            let isLonger = deviationPercent > 0
            let color: Color = isLonger ? .orange : .blue
            let isBeyond = deviationPercent > EffortReviewText.scale.upperBound || deviationPercent < EffortReviewText.scale.lowerBound
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: max(2, abs(end - centre)))
                    .offset(x: min(centre, end))
                Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 1.5).offset(x: centre)
                if isBeyond {
                    Image(systemName: isLonger ? "chevron.right" : "chevron.left")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: isLonger ? width - 14 : 4)
                }
            }
        }
    }
}
