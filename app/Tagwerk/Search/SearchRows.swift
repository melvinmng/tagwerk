import GitHubKit
import SwiftUI
import TagwerkCore

/// The line below a title that shows where a word was found outside the title ("Notiz: …").
struct SearchSnippetLine: View {
    let snippet: SearchMatch.Snippet

    var body: some View {
        (Text(verbatim: "\(SearchTexts.snippetLabel(snippet.field)): ").foregroundStyle(.secondary)
            + Text(SearchTexts.highlighted(snippet.text, ranges: snippet.ranges)))
            .font(.caption)
            .lineLimit(2)
            .accessibilityHidden(true)
    }
}

/// An event hit: date and time on the left, highlighted title, calendar and place, series note.
struct SearchEventRow: View {
    let row: EventRow
    let match: SearchMatch
    let calendarName: String?
    let isDeadline: Bool
    let isPast: Bool
    let now: Date
    let calendar: Calendar

    var body: some View {
        let event = row.event
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(SearchTexts.eventDate(event, now: now, calendar: calendar)).font(.caption.weight(.semibold))
                Text(SearchTexts.eventTime(event, calendar: calendar)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 72, alignment: .trailing)
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(event.title, ranges: match.titleRanges))
                    .foregroundStyle(isPast ? .secondary : .primary)
                if isDeadline {
                    Label("Deadline", systemImage: "flag.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                if let snippet = match.snippet { SearchSnippetLine(snippet: snippet) }
                if let series = SearchTexts.seriesText(row, calendar: calendar) {
                    Text(series).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let calendarName { parts.append(calendarName) }
        if let location = row.event.location, !location.isEmpty { parts.append(location) }
        if isPast, let ago = SearchTexts.agoText(row.event, now: now, calendar: calendar) { parts.append(ago) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = [String(localized: "Termin"), row.event.title,
                     SearchTexts.eventDate(row.event, now: now, calendar: calendar),
                     SearchTexts.eventTime(row.event, calendar: calendar)]
        if isDeadline { parts.append(String(localized: "Deadline")) }
        if let subtitle { parts.append(subtitle) }
        if let series = SearchTexts.seriesText(row, calendar: calendar) { parts.append(series) }
        return parts.joined(separator: ", ")
    }
}

/// An open task hit: the task row of the lists with highlighted title and a snippet line.
struct SearchTaskRow: View {
    let item: TaskItem
    let match: SearchMatch
    let now: Date
    let calendar: Calendar
    var isReadOnly = false
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TaskRow(item: item, section: section(for: item, now: now, calendar: calendar), now: now, calendar: calendar,
                    isReadOnly: isReadOnly, titleText: SearchTexts.highlighted(item.title, ranges: match.titleRanges),
                    onComplete: onComplete)
            if let snippet = match.snippet {
                SearchSnippetLine(snippet: snippet).padding(.leading, 34)
            }
        }
    }
}

/// A completed task hit: filled circle, grey title, date, list and the number of equal reminders.
struct SearchCompletedRow: View {
    let group: CompletedGroup
    let match: SearchMatch
    let now: Date
    let calendar: Calendar

    var body: some View {
        let item = group.latest.item
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(item.title, ranges: match.titleRanges)).foregroundStyle(.secondary)
                Text(SearchTexts.completedText(group, calendar: calendar, now: now)).font(.caption).foregroundStyle(.secondary)
                if let snippet = match.snippet { SearchSnippetLine(snippet: snippet) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText(item))
    }

    private func spokenText(_ item: TaskItem) -> String {
        [String(localized: "Erledigte Aufgabe"), item.title, SearchTexts.completedText(group, calendar: calendar, now: now)]
            .joined(separator: ", ")
    }
}

/// A row with a progress indicator while the events are being fetched.
struct SearchLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Termine werden durchsucht …").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A GitHub hit from the online search: dashed circle (nothing to check off here), number and title, the reason it
/// is not among the tasks, repository and date. Read-only; a tap opens GitHub.
struct SearchOnlineRow: View {
    let issue: OnlineIssue
    let now: Date
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.dashed").font(.title3).foregroundStyle(.secondary).opacity(0.45).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "#\(issue.number) \(issue.title)")
                    .foregroundStyle(issue.marker == .closed ? .secondary : .primary)
                if let marker = issue.marker {
                    Text(SearchTexts.markerText(marker))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(SearchTexts.onlineSubtitle(issue, now: now, calendar: calendar)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
        .accessibilityHint("Öffnet das Issue auf GitHub")
    }

    private var spokenText: String {
        var parts = ["GitHub", "#\(issue.number)", issue.title]
        if let marker = issue.marker { parts.append(SearchTexts.markerText(marker)) }
        parts.append(SearchTexts.onlineSubtitle(issue, now: now, calendar: calendar))
        return parts.joined(separator: ", ")
    }
}

/// The last row of "Aufgaben": the one tap after which a search text goes to GitHub.
struct SearchOnlineAskRow: View {
    let state: SearchModel.OnlineState
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .failed(let error) = state {
                Text(SearchTexts.onlineError(error)).font(.footnote).foregroundStyle(.red)
            }
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: "network").frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isFailed ? "Erneut versuchen" : "Auf GitHub suchen")
                        Text("auch geschlossene und fremde").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
