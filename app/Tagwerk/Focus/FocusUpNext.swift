import Foundation
import TagwerkCore

/// One line of the section "Danach" in the focus sheet (FO6b): what comes next today. Read only.
struct FocusUpNextRow: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The end of the time block the session was started from.
        case blockEnd(title: String)
        /// The moment to leave for the next event, with the travel time.
        case departure(minutes: Int)
        case entry(title: String, endMinutes: Int)
    }

    let startMinutes: Int
    let kind: Kind

    var id: String {
        switch kind {
        case .blockEnd: "block-end-\(startMinutes)"
        case .departure: "departure-\(startMinutes)"
        case .entry(let title, _): "entry-\(startMinutes)-\(title)"
        }
    }
}

enum FocusUpNext {
    /// The next rows of today after `nowMinutes`: the end of the session's block first, then entries and departures
    /// in time order; gaps, the lunch break and past entries are left out. At most `limit` rows.
    static func rows(timeline: [TimelineRow], blockEventID: String?, nowMinutes: Int, dayStart: Date,
                     limit: Int = 3) -> [FocusUpNextRow] {
        func minutes(_ date: Date) -> Int { Int((date.timeIntervalSince(dayStart) / 60).rounded(.down)) }
        var blockEnd: FocusUpNextRow?
        var others: [FocusUpNextRow] = []
        for row in timeline {
            switch row {
            case .event(let event), .block(let event, _):
                if event.id == blockEventID {
                    let end = minutes(event.end)
                    if end > nowMinutes { blockEnd = FocusUpNextRow(startMinutes: end, kind: .blockEnd(title: event.title)) }
                } else if minutes(event.start) >= nowMinutes {
                    others.append(FocusUpNextRow(startMinutes: minutes(event.start),
                                                 kind: .entry(title: event.title, endMinutes: minutes(event.end))))
                }
            case .travel(let segment):
                if segment.range.lowerBound >= nowMinutes {
                    others.append(FocusUpNextRow(startMinutes: segment.range.lowerBound, kind: .departure(minutes: segment.minutes)))
                }
            case .lunch, .gap:
                break
            }
        }
        // The sort is stable: rows at the same minute keep the order of the timeline.
        let sorted = others.enumerated().sorted { ($0.element.startMinutes, $0.offset) < ($1.element.startMinutes, $1.offset) }.map(\.element)
        return Array(((blockEnd.map { [$0] } ?? []) + sorted).prefix(limit))
    }
}
