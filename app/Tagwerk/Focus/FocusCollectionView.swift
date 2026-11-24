import SwiftUI
import TagwerkCore

/// The collection: one brick per focus session of a minute or more, stacked per weekday and grouped by week (FO8c).
/// The height of a brick follows its stage, a dashed outline marks a session that ended early. Drawn with shapes only.
struct FocusCollectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @ScaledMetric(relativeTo: .body) private var columnHeight = 150.0

    private var weeks: [FocusCollectionWeek] {
        let sessions = environment.focusStore.finishedSessions().compactMap { record -> (endedAt: Date, piece: FocusRewardPiece, focusedSeconds: Int)? in
            guard let piece = record.piece else { return nil }
            return (record.endedAt ?? record.start, piece, record.focusedSeconds)
        }
        return FocusCollection.weeks(sessions: sessions, calendar: .tagwerk)
    }

    var body: some View {
        let weeks = weeks
        List {
            if weeks.isEmpty {
                ContentUnavailableView("Noch nichts gesammelt", systemImage: "timer",
                                       description: Text("Jede Fokus-Sitzung ab einer Minute ergibt einen Baustein."))
            }
            ForEach(weeks) { week in
                Section {
                    weekView(week)
                        .padding(.vertical, 4)
                } header: {
                    Text(FocusTimerText.weekHeader(start: week.start, focusedMinutes: week.focusedMinutes))
                } footer: {
                    Text(FocusTimerText.collectionSummary(week.summary))
                }
            }
            if !weeks.isEmpty {
                Section {} footer: {
                    Text("Höhe nach Dauer (1, 10, 25, 50, 90 min) · gestrichelt: vorzeitig beendet")
                }
            }
        }
        .navigationTitle("Sammlung")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func weekView(_ week: FocusCollectionWeek) -> some View {
        let names = FocusTimerText.weekdayNames(calendar: .tagwerk)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 6) {
                    stack(of: week.days[index])
                    Text(names.short[index])
                        .font(.caption2)
                        .foregroundStyle(.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FocusTimerText.dayAccessibility(weekday: names.long[index], bricks: week.days[index]))
            }
        }
    }

    private func stack(of bricks: [FocusBrick]) -> some View {
        let heights = FocusCollection.heights(of: bricks, available: columnHeight)
        return VStack(spacing: FocusCollection.brickSpacing) {
            Spacer(minLength: 0)
            // The newest brick sits on top, the first of the day at the bottom.
            ForEach(Array(bricks.enumerated()).reversed(), id: \.offset) { index, brick in
                BrickShape(isEndedEarly: brick.piece.isEndedEarly)
                    .frame(height: heights[index])
            }
        }
        .frame(height: columnHeight)
    }
}

/// One brick: filled in the accent colour, or a dashed outline without fill when the session ended early.
private struct BrickShape: View {
    let isEndedEarly: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if isEndedEarly {
            shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        } else {
            shape.fill(Color.accentColor)
        }
    }
}
