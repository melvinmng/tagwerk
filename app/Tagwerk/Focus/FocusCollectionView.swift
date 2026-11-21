import SwiftUI
import TagwerkCore

/// The collection: one brick per focus session of a minute or more, grouped by week. The symbols are neutral
/// placeholders until the bricks per weekday replace them (F2).
struct FocusCollectionView: View {
    @Environment(AppEnvironment.self) private var environment

    private struct Week: Identifiable {
        let start: Date
        let pieces: [FocusRewardPiece]
        var id: Date { start }
    }

    private var weeks: [Week] {
        let calendar = Calendar.tagwerk
        let finished = environment.focusStore.finishedSessions().filter { $0.piece != nil }
        let grouped = Dictionary(grouping: finished) {
            calendar.dateInterval(of: .weekOfYear, for: $0.endedAt ?? $0.start)?.start ?? $0.start
        }
        return grouped.map { Week(start: $0.key, pieces: $0.value.compactMap(\.piece)) }.sorted { $0.start > $1.start }
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(Array(week.pieces.enumerated()), id: \.offset) { _, piece in
                            Image(systemName: piece.isEndedEarly ? "\(piece.stage.rawValue).circle" : "\(piece.stage.rawValue).circle.fill")
                                .font(.title)
                                .foregroundStyle(piece.isEndedEarly ? Color.secondary : Color.accentColor)
                                .accessibilityLabel(piece.isEndedEarly ? Text("Vorzeitig beendet, Stufe \(piece.stage.rawValue)") : Text("Abgeschlossen, Stufe \(piece.stage.rawValue)"))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Woche ab \(week.start.formatted(.dateTime.day().month()))")
                } footer: {
                    Text(FocusTimerText.collectionSummary(FocusReward.summary(of: week.pieces)))
                }
            }
        }
        .navigationTitle("Sammlung")
        .navigationBarTitleDisplayMode(.inline)
    }
}
