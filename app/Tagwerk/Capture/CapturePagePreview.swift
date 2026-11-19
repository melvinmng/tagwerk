import SwiftUI
import TagwerkCore

/// The neighbouring day of "Erfassen" while the page is dragged: head and the day's calories and water from the
/// local entries; no Health query, no interaction.
struct CapturePagePreview: View {
    let model: CaptureModel
    let day: PlanDay

    var body: some View {
        let settings = model.settings
        let intake = model.summary(for: day)
        let remaining = IntakeFormat.remaining(goal: settings.goalKilocalories, intake: intake)
        let range = day...day
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(PlanHeaderText.caption(scope: .day, anchor: day, today: model.today, range: range, calendar: model.calendar))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(PlanHeaderText.title(scope: .day, anchor: day, range: range, calendar: model.calendar)).font(.title3.bold())
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(IntakeFormat.kcalNumber(intake.kcal, estimated: intake.hasEstimate)) / \(IntakeFormat.grouped(settings.goalKilocalories)) kcal")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(remaining.text).font(.subheadline).foregroundStyle(remaining.isOver ? .orange : .secondary)
                }
                ProgressView(value: min(1, intake.kcal / Double(max(1, settings.goalKilocalories))))
                    .tint(remaining.isOver ? .orange : .green)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Wasser").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: "\(IntakeFormat.liters(intake.waterMilliliters)) / \(IntakeFormat.liters(settings.goalWaterMilliliters))")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                ProgressView(value: min(1, Double(intake.waterMilliliters) / Double(max(1, settings.goalWaterMilliliters)))).tint(.cyan)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 120)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The neighbouring week of the weekly review while the page is dragged: only the week title.
struct WeekReviewPagePreview: View {
    let model: WeekReviewModel
    let weekStart: PlanDay

    var body: some View {
        let range = weekStart...weekStart.adding(days: 6, calendar: model.calendar)
        VStack(alignment: .leading, spacing: 0) {
            Text(PlanHeaderText.caption(scope: .week, anchor: weekStart, today: model.today, range: range, calendar: model.calendar))
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(PlanHeaderText.title(scope: .week, anchor: weekStart, range: range, calendar: model.calendar)).font(.title3.bold())
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 120)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
