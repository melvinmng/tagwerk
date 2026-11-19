import SwiftUI
import TagwerkCore

/// The collection: one piece per finished focus session, grouped by week. The symbols are neutral placeholders; the
/// look of the stages is a design decision (#188).
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
                                       description: Text("Jede beendete Fokus-Sitzung ergibt ein Stück. Wer früher abbricht, bekommt ein gewelktes."))
            }
            ForEach(weeks) { week in
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(Array(week.pieces.enumerated()), id: \.offset) { _, piece in
                            Image(systemName: piece.isWilted ? "\(piece.stage.rawValue).circle" : "\(piece.stage.rawValue).circle.fill")
                                .font(.title)
                                .foregroundStyle(piece.isWilted ? Color.secondary : Color.accentColor)
                                .accessibilityLabel(piece.isWilted ? Text("Gewelkt, Stufe \(piece.stage.rawValue)") : Text("Gewachsen, Stufe \(piece.stage.rawValue)"))
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
