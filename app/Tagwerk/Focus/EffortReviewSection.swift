import SwiftUI
import TagwerkCore

/// "Schätzung und Ist" in the weekly review: how long tasks took against their estimate, per source and per label, from
/// the last eight weeks up to the shown week. Measured from time blocks plus focus time outside them; stays on the iPhone.
struct EffortReviewSection: View {
    @Environment(AppEnvironment.self) private var environment
    let model: WeekReviewModel

    var body: some View {
        let data = reviewData
        Section {
            if data.groups.isEmpty {
                Text("Noch zu wenige Messungen.").foregroundStyle(.secondary)
            }
            ForEach(Array(data.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(EffortReviewText.name(of: group.kind)) · \(EffortReviewText.count(group.count))")
                    Text(EffortReviewText.detail(of: group)).font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if data.withoutEstimate > 0 {
                LabeledContent("Ohne Schätzung gemessen", value: "\(data.withoutEstimate)")
            }
            LabeledContent("Fokus in dieser Woche", value: CapacityText.duration(data.focusMinutes))
            LabeledContent("Messungen in dieser Woche", value: "\(data.samplesThisWeek)")
        } header: {
            Text("Schätzung und Ist")
        } footer: {
            Text("Gemessen über Zeitblöcke; Fokus-Timer zählt nur außerhalb der Blöcke, letzte 8 Wochen.")
        }
    }

    private struct ReviewData {
        var groups: [EffortGroup]
        var withoutEstimate: Int
        var focusMinutes: Int
        var samplesThisWeek: Int
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
