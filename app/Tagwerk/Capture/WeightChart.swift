import Charts
import SwiftUI
import TagwerkCore

/// The weight chart (decision KG3a): a point for every measurement, the 7-day mean as a line and the target weight as a dashed line
/// that steps where the goal plan changes. VoiceOver reads the summary, not the single marks.
struct WeightChart: View {
    let measurements: [WeightMeasurement]
    let meanLine: [(day: PlanDay, kilograms: Double)]
    let targets: [TargetSegment]
    let period: WeightPeriod
    let calendar: Calendar
    let summary: String

    private func date(_ day: PlanDay) -> Date { day.startDate(in: calendar) }

    var body: some View {
        Chart {
            ForEach(measurements) { measurement in
                PointMark(x: .value("Zeit", measurement.date), y: .value("Gewicht", measurement.kilograms))
                    .symbolSize(28)
                    .foregroundStyle(Color.secondary.opacity(0.6)) // system-colour: chart point, not text
            }
            ForEach(Array(meanLine.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Zeit", date(point.day).addingTimeInterval(12 * 3600)), y: .value("7-Tage-Mittel", point.kilograms),
                         series: .value("Linie", "mean"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(Array(targets.enumerated()), id: \.offset) { index, segment in
                RuleMark(xStart: .value("Von", date(segment.first)), xEnd: .value("Bis", date(segment.last).addingTimeInterval(86_400)),
                         y: .value("Ziel", segment.kilograms))
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            switch period {
            case .week: AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.short)) }
            case .month: AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
            }
            case .threeMonths, .year: AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
            }
        }
        .environment(\.calendar, calendar)
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gewicht")
        .accessibilityValue(summary)
    }
}

/// The body fat as its own small chart under the weight chart: a different scale, so a second line in the same chart would flatten
/// both. Only drawn with the switch on and at least one value.
struct BodyFatChart: View {
    let measurements: [WeightMeasurement]
    let calendar: Calendar

    var body: some View {
        let points = measurements.compactMap { measurement in measurement.bodyFatPercent.map { (measurement.date, $0) } }
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Zeit", point.0), y: .value("Körperfett", point.1))
                    .foregroundStyle(Color.orange)
                PointMark(x: .value("Zeit", point.0), y: .value("Körperfett", point.1))
                    .symbolSize(24)
                    .foregroundStyle(Color.orange)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .environment(\.calendar, calendar)
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Körperfett")
        .accessibilityValue(points.last.map { WeightFormat.bodyFat($0.1) } ?? "")
    }
}
