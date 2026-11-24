import Charts
import SwiftUI
import TagwerkCore

/// The bars of the eaten energy per day (week, month) or the mean per day of a month (year), with the budget as a line. The part of a
/// bar above the budget is orange. Days without entries are gaps. VoiceOver reads the summary, not the single marks.
struct IntakeChart: View {
    let buckets: [TrendBucket]
    let period: TrendPeriod
    let calendar: Calendar
    let summary: String

    private func date(_ day: PlanDay) -> Date { day.startDate(in: calendar) }
    private var unit: Calendar.Component { period == .year ? .month : .day }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                if let eaten = bucket.eatenKcal {
                    let within = min(eaten, bucket.budgetKcal ?? eaten)
                    BarMark(x: .value("Zeitraum", date(bucket.first), unit: unit), y: .value("gegessen", within))
                        .foregroundStyle(by: .value("Art", Kind.eaten))
                    if let budget = bucket.budgetKcal, eaten > budget {
                        BarMark(x: .value("Zeitraum", date(bucket.first), unit: unit), y: .value("über Budget", eaten - budget))
                            .foregroundStyle(by: .value("Art", Kind.over))
                    }
                }
            }
            ForEach(buckets) { bucket in
                if let budget = bucket.budgetKcal {
                    LineMark(x: .value("Zeitraum", date(bucket.first), unit: unit), y: .value("Budget", budget), series: .value("Linie", "Budget"))
                        .interpolationMethod(.stepCenter)
                        .foregroundStyle(by: .value("Art", Kind.budget))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
        .chartForegroundStyleScale([Kind.eaten: Color.green, Kind.over: Color.orange, Kind.budget: Color.secondary])
        .chartXAxis {
            switch period {
            case .week: AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.short)) }
            case .month: AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
            }
            case .year: AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) }
            }
        }
        .environment(\.calendar, calendar)
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kalorien")
        .accessibilityValue(summary)
    }

    /// The legend entries, in the language of the app (a plotted string is shown as it is).
    private enum Kind {
        static let eaten = String(localized: "gegessen")
        static let over = String(localized: "über Budget")
        static let budget = String(localized: "Budget des Tages")
    }
}
