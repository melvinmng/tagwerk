import Charts
import SwiftUI
import TagwerkCore

/// Planned and invested hours per week, two bars per week, on the same weeks as the progress chart. The legend carries the names;
/// the bars differ in colour and position. VoiceOver reads the summary, not the single marks.
struct ProjectTimeChart: View {
    let weeks: [ProjectTimeWeek]
    let calendar: Calendar
    let summary: String

    var body: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Woche", week.start, unit: .weekOfYear), y: .value("Stunden", week.plannedSeconds / 3600))
                    .foregroundStyle(by: .value("Art", Kind.planned))
                    .position(by: .value("Art", Kind.planned))
                BarMark(x: .value("Woche", week.start, unit: .weekOfYear), y: .value("Stunden", week.investedSeconds / 3600))
                    .foregroundStyle(by: .value("Art", Kind.invested))
                    .position(by: .value("Art", Kind.invested))
            }
        }
        .chartForegroundStyleScale([Kind.planned: Color.orange, Kind.invested: Color.teal])
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: strideWeeks)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
            }
        }
        .chartYAxisLabel("Stunden")
        .environment(\.calendar, calendar)
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eingeplante und investierte Zeit je Woche")
        .accessibilityValue(summary)
        .accessibilityIdentifier(AccessibilityID.ProjectProgress.timeChart)
    }

    /// The same label spacing as the progress chart.
    private var strideWeeks: Int {
        switch weeks.count {
        case ...6: 1
        case ...16: 2
        case ...30: 4
        default: 8
        }
    }

    /// The legend entries, in the language of the app (a plotted string is shown as it is).
    private enum Kind {
        static let planned = String(localized: "eingeplant")
        static let invested = String(localized: "investiert")
    }
}
