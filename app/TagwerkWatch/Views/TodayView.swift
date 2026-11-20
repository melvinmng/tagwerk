import SwiftUI
import TagwerkCore

/// "Als Nächstes" large, below it the next entries of the day.
struct TodayView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let calendar = Calendar.watch
        let snapshot = store.display(at: now)
        let next = snapshot.map { WatchNextUp.select(snapshot: $0, now: now, calendar: calendar) } ?? .stale
        let text = WatchNextUpText.make(next, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(text.caption).font(.footnote).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: text.symbolName).foregroundStyle(.tint)
                    if let time = text.time { Text(time).font(.headline).monospacedDigit() }
                    if let suffix = text.suffix { Text(suffix).font(.footnote).foregroundStyle(.secondary) }
                }
                if let title = text.title {
                    Text(title).font(.title3).lineLimit(3)
                }
                if let snapshot, !upcoming(snapshot, after: next, now: now, calendar: calendar).isEmpty {
                    Divider()
                    ForEach(upcoming(snapshot, after: next, now: now, calendar: calendar)) { entry in
                        HStack(spacing: 6) {
                            Text(DateText.time(entry.start, calendar: calendar)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            Text(entry.title).font(.footnote).lineLimit(1)
                        }
                    }
                }
                SyncHint().padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Heute")
    }

    /// The next entries of today after the one shown above, at most three.
    private func upcoming(_ snapshot: WatchSnapshot, after next: WatchNextUp, now: Date, calendar: Calendar) -> [SnapshotEntry] {
        guard !snapshot.isStale(at: now, calendar: calendar) else { return [] }
        var shownID: String?
        if case .entry(let entry, _) = next { shownID = entry.id }
        return Array(snapshot.entries
            .filter { !$0.isAllDay && PlanDay(date: $0.start, calendar: calendar) == snapshot.day && $0.end > now && $0.id != shownID }
            .sorted { $0.start < $1.start }
            .prefix(3))
    }
}
