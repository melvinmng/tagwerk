import GitHubKit
import SwiftUI
import TagwerkCore

/// The line below a title that shows where a word was found outside the title ("Notiz: …").
struct SearchSnippetLine: View {
    let snippet: SearchMatch.Snippet

    var body: some View {
        (Text(verbatim: "\(SearchTexts.snippetLabel(snippet.field)): ").foregroundStyle(.secondaryText)
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
                Text(SearchTexts.eventTime(event, calendar: calendar)).font(.caption).foregroundStyle(.secondaryText)
            }
            .frame(minWidth: 72, alignment: .trailing)
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(event.title, ranges: match.titleRanges))
                    .foregroundStyle(isPast ? Color.secondaryText : Color.primary)
                if isDeadline {
                    Label("Deadline", systemImage: "flag.fill").font(.caption.weight(.semibold)).foregroundStyle(.orangeText)
                }
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondaryText) }
                if let snippet = match.snippet { SearchSnippetLine(snippet: snippet) }
                if let series = SearchTexts.seriesText(row, calendar: calendar) {
                    Text(series).font(.caption).foregroundStyle(.secondaryText)
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
    var reminderMark: ReminderMark?
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TaskRow(item: item, section: section(for: item, now: now, calendar: calendar), now: now, calendar: calendar,
                    isReadOnly: isReadOnly, reminderMark: reminderMark,
                    titleText: SearchTexts.highlighted(item.title, ranges: match.titleRanges), onComplete: onComplete)
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
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(item.title, ranges: match.titleRanges)).foregroundStyle(.secondaryText)
                Text(SearchTexts.completedText(group, calendar: calendar, now: now)).font(.caption).foregroundStyle(.secondaryText)
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
            Text("Termine werden durchsucht …").foregroundStyle(.secondaryText)
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
            Image(systemName: "circle.dashed").font(.title3).foregroundStyle(.secondaryText).opacity(0.45).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "#\(issue.number) \(issue.title)")
                    .foregroundStyle(issue.marker == .closed ? Color.secondaryText : Color.primary)
                if let marker = issue.marker {
                    Text(SearchTexts.markerText(marker))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(SearchTexts.onlineSubtitle(issue, now: now, calendar: calendar)).font(.caption).foregroundStyle(.secondaryText)
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
                Text(SearchTexts.onlineError(error)).font(.footnote).foregroundStyle(.redText)
            }
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: "network").frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isFailed ? "Erneut versuchen" : "Auf GitHub suchen")
                        Text("auch geschlossene und fremde").font(.caption).foregroundStyle(.secondaryText)
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

/// A note hit: first line as the title, kind and day below, then the passage that matched.
struct SearchNoteRow: View {
    let note: NoteSearchItem
    let match: SearchMatch
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.isConcealed ? "lock.fill" : "note.text").font(.title3).foregroundStyle(.secondaryText).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(title, ranges: match.titleRanges)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondaryText)
                // A hidden note shows no passage: that would tell what its text holds.
                if !note.isConcealed, let snippet = match.snippet { SearchSnippetLine(snippet: snippet) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([String(localized: "Notiz"), title, subtitle].joined(separator: ", "))
    }

    /// The kind and day; a hidden note shows "Ordner · Gesperrt" instead.
    private var subtitle: String {
        note.isConcealed ? "\(note.kindLabel) · " + String(localized: "Gesperrt")
            : SearchTexts.noteSubtitle(kindLabel: note.kindLabel, updatedAt: note.updatedAt, dayKey: note.dayKey, calendar: calendar)
    }

    /// The first line of the text, as the search document reads it.
    private var title: String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }
}

/// A shopping item hit: the circle checks it off, the row opens the list; "Einkauf" marks the source.
struct SearchShoppingRow: View {
    let item: ShoppingSearchItem
    let match: SearchMatch
    let onCheckOff: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { onCheckOff?() } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(onCheckOff == nil)
            .accessibilityLabel("Abhaken")
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(item.name, ranges: match.titleRanges))
                if let quantity = item.quantity { Text(quantity).font(.caption).foregroundStyle(.secondaryText) }
                if let snippet = match.snippet, snippet.field != .quantity { SearchSnippetLine(snippet: snippet) }
            }
            Spacer(minLength: 8)
            Text("Einkauf").font(.caption).foregroundStyle(.secondaryText)
        }
        .contentShape(Rectangle())
    }
}

/// A hit in the settings: the title and the way to it ("Erfassen", "KI › Spracheingabe und Vorlesen"); a tap opens the page.
struct SearchSettingRow: View {
    let item: SettingsSearchItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gearshape").font(.title3).foregroundStyle(.secondaryText).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if !item.pathText.isEmpty { Text(item.pathText).font(.caption).foregroundStyle(.secondaryText) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.secondaryText).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A hit among the repositories and projects of the GitHub account: the title with the words found, below it the kind ("Repository",
/// "GitHub-Projekt") and the owner or organisation. A tap opens the progress of the project.
struct SearchGitHubTargetRow: View {
    let item: GitHubTargetSearchItem
    let titleRanges: [Range<String.Index>]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.kind == .repository ? "shippingbox" : "list.bullet.rectangle")
                .font(.title3).foregroundStyle(.secondaryText).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchTexts.highlighted(item.title, ranges: titleRanges))
                Text(SearchTexts.githubTargetSubtitle(item)).font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.secondaryText).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SearchTexts.githubTargetAccessibility(item))
    }
}
