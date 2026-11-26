import Charts
import SwiftUI
import TagwerkCore

/// Two bars per week (done and new) and the open stock at the end of the week as a line. The legend carries the names; the bars differ
/// in colour and position, the line in dash. VoiceOver reads the summary, not the single marks.
struct ProjectProgressChart: View {
    let buckets: [ProjectWeekBucket]
    let calendar: Calendar
    let summary: String

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Woche", bucket.start, unit: .weekOfYear), y: .value("Anzahl", bucket.completed))
                    .foregroundStyle(by: .value("Art", Kind.completed))
                    .position(by: .value("Art", Kind.completed))
                BarMark(x: .value("Woche", bucket.start, unit: .weekOfYear), y: .value("Anzahl", bucket.created))
                    .foregroundStyle(by: .value("Art", Kind.created))
                    .position(by: .value("Art", Kind.created))
            }
            ForEach(buckets) { bucket in
                LineMark(x: .value("Woche", bucket.start, unit: .weekOfYear), y: .value("Anzahl", bucket.openAtEnd),
                         series: .value("Linie", "open"))
                    .foregroundStyle(by: .value("Art", Kind.open))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([Kind.completed: Color.green, Kind.created: Color.blue, Kind.open: Color.secondary])
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: strideWeeks)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
            }
        }
        .environment(\.calendar, calendar)
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Erledigt und neu je Woche")
        .accessibilityValue(summary)
        .accessibilityIdentifier(AccessibilityID.ProjectProgress.chart)
    }

    /// A label every week for a month, every few weeks for longer periods.
    private var strideWeeks: Int {
        switch buckets.count {
        case ...6: 1
        case ...16: 2
        case ...30: 4
        default: 8
        }
    }

    /// The legend entries, in the language of the app (a plotted string is shown as it is).
    private enum Kind {
        static let completed = String(localized: "erledigt")
        static let created = String(localized: "neu")
        static let open = String(localized: "offen am Ende der Woche")
    }
}
