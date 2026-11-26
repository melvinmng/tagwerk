import Foundation

/// Kind filter of the search sheet.
public enum SearchFilter: Sendable, CaseIterable {
    case all, events, tasks
}

/// Sections of the result list. The declaration order is the display order.
public enum SearchSectionKind: Sendable, Hashable, CaseIterable {
    case upcomingEvents, openTasks, completedTasks, online, pastEvents, notes, shopping, settings
}

/// State of a GitHub issue found online; the first applicable one is shown.
public enum OnlineIssueMarker: Sendable, Equatable {
    case closed, unassigned, assignedToOthers, noProject
}

/// A GitHub issue found by the online search. Read-only.
public struct OnlineIssue: Sendable, Hashable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let repository: String
    public let url: URL
    public let updatedAt: Date
    public let marker: OnlineIssueMarker?
    /// GitHub logins assigned to the issue.
    public let assignees: [String]

    public init(id: String, number: Int, title: String, repository: String, url: URL, updatedAt: Date, marker: OnlineIssueMarker?,
                assignees: [String] = []) {
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.url = url
        self.updatedAt = updatedAt
        self.marker = marker
        self.assignees = assignees
    }
}

/// A note as the search sees it.
public struct NoteSearchItem: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let text: String
    public let kindLabel: String
    public let updatedAt: Date
    /// "YYYY-MM-DD" of a morning or evening note; `nil` for the user's own notes.
    public let dayKey: String?
    /// The routine day this hit opens instead of a note: a day of "Tagesstart" that only has gratitude. `nil` for notes.
    public let routineDay: PlanDay?
    /// The note is hidden by the lock: `text` holds the title line only and the row shows no passage (NL4a).
    public let isConcealed: Bool
    /// The text recognised in the scans of the note (the app search only; empty for the assistant, which never gets it, and for a hidden note).
    public let scanText: String

    public init(id: UUID, text: String, kindLabel: String, updatedAt: Date, dayKey: String? = nil, routineDay: PlanDay? = nil,
                isConcealed: Bool = false, scanText: String = "") {
        self.isConcealed = isConcealed
        self.scanText = scanText
        self.id = id
        self.text = text
        self.kindLabel = kindLabel
        self.updatedAt = updatedAt
        self.dayKey = dayKey
        self.routineDay = routineDay
    }
}

/// An open shopping item as the search sees it.
public struct ShoppingSearchItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let quantity: String?

    public init(id: String, name: String, quantity: String?) {
        self.id = id
        self.name = name
        self.quantity = quantity
    }
}

/// A hit in the settings as the search sees it: the caller matched it with the index of the settings (titles and keywords), so the
/// search does not filter it again. `pathText` names the pages that lead to it ("Erfassen"), empty for a row of the main list.
public struct SettingsSearchItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let pathText: String

    public init(id: String, title: String, pathText: String) {
        self.id = id
        self.title = title
        self.pathText = pathText
    }
}

/// Everything the search filters. Events are already prepared (time blocks dropped, duplicates merged).
public struct SearchInput: Sendable {
    /// `nil`: not loaded yet or no calendar access.
    public var events: [CalendarEvent]?
    public var calendarNames: [String: String]
    public var openTasks: [TaskItem]
    public var completed: [CompletedTask]
    /// `nil`: not searched online for the current query.
    public var online: [OnlineIssue]?
    /// Any order; the results sort by `updatedAt`, newest first.
    public var notes: [NoteSearchItem]
    /// Already in the order of the shopping page.
    public var shopping: [ShoppingSearchItem]
    /// Hits in the settings, best first; only the first `SearchResults.settingsLimit` are shown.
    public var settings: [SettingsSearchItem]

    public init(events: [CalendarEvent]? = nil, calendarNames: [String: String] = [:], openTasks: [TaskItem] = [],
                completed: [CompletedTask] = [], online: [OnlineIssue]? = nil, notes: [NoteSearchItem] = [],
                shopping: [ShoppingSearchItem] = [], settings: [SettingsSearchItem] = []) {
        self.events = events
        self.calendarNames = calendarNames
        self.openTasks = openTasks
        self.completed = completed
        self.online = online
        self.notes = notes
        self.shopping = shopping
        self.settings = settings
    }
}

public enum SearchRow: Sendable, Identifiable {
    case event(EventRow, SearchMatch)
    case task(TaskItem, SearchMatch)
    case completed(CompletedGroup, SearchMatch)
    case online(OnlineIssue)
    case note(NoteSearchItem, SearchMatch)
    case shopping(ShoppingSearchItem, SearchMatch)
    case setting(SettingsSearchItem)

    public var id: String {
        switch self {
        case .event(let row, _): "event-\(row.id)"
        case .task(let item, _): "task-\(item.id.source.rawValue)-\(item.id.rawValue)"
        case .completed(let group, _): "completed-\(group.id.source.rawValue)-\(group.id.rawValue)"
        case .online(let issue): "online-\(issue.id)"
        case .note(let note, _): "note-\(note.id.uuidString)"
        case .shopping(let item, _): "shopping-\(item.id)"
        case .setting(let item): "setting-\(item.id)"
        }
    }
}

public struct SearchSection: Sendable, Identifiable {
    public var id: SearchSectionKind { kind }
    public let kind: SearchSectionKind
    public let rows: [SearchRow]
}

public struct SearchResults: Sendable {
    public static let empty = SearchResults(sections: [])

    /// Sections in display order; empty sections are left out.
    public let sections: [SearchSection]

    /// Rows of the section "Einstellungen"; more hits are found in the tab "Einstellungen" itself.
    public static let settingsLimit = 5

    public var isEmpty: Bool { sections.isEmpty }

    public static func make(query: SearchQuery, filter: SearchFilter, includeCompleted: Bool, input: SearchInput,
                            now: Date, calendar: Calendar) -> SearchResults {
        var rowsByKind: [SearchSectionKind: [SearchRow]] = [:]

        if filter != .tasks, let events = input.events {
            var matches: [String: SearchMatch] = [:]
            var matching: [CalendarEvent] = []
            for event in events {
                let document = SearchDocument(event: event, calendarName: input.calendarNames[event.calendarID])
                if let match = query.match(document) {
                    matches[event.id] = match
                    matching.append(event)
                }
            }
            let grouped = EventSeriesGrouping.rows(matching, now: now, calendar: calendar)
            rowsByKind[.upcomingEvents] = grouped.upcoming.compactMap { row in matches[row.event.id].map { .event(row, $0) } }
            rowsByKind[.pastEvents] = grouped.past.compactMap { row in matches[row.event.id].map { .event(row, $0) } }
        }

        if filter != .events {
            var taskMatches: [TaskID: SearchMatch] = [:]
            var matching: [TaskItem] = []
            for task in input.openTasks {
                if let match = query.match(SearchDocument(task: task)) {
                    taskMatches[task.id] = match
                    matching.append(task)
                }
            }
            rowsByKind[.openTasks] = sortedTasks(matching, calendar: calendar).compactMap { task in
                taskMatches[task.id].map { .task(task, $0) }
            }

            if includeCompleted {
                var completedMatches: [TaskID: SearchMatch] = [:]
                var matchingCompleted: [CompletedTask] = []
                for task in input.completed {
                    if let match = query.match(SearchDocument(task: task.item)) {
                        completedMatches[task.id] = match
                        matchingCompleted.append(task)
                    }
                }
                rowsByKind[.completedTasks] = CompletedGrouping.groups(matchingCompleted).compactMap { group in
                    completedMatches[group.latest.id].map { .completed(group, $0) }
                }
            }

            rowsByKind[.online] = input.online?.map { .online($0) }
        }

        if filter == .all {
            rowsByKind[.notes] = input.notes
                .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
                .compactMap { note in
                    query.match(SearchDocument(noteText: note.text, kindLabel: note.kindLabel, scanText: note.scanText)).map { .note(note, $0) }
                }
            rowsByKind[.shopping] = input.shopping.compactMap { item in
                query.match(SearchDocument(shoppingName: item.name, quantity: item.quantity)).map { .shopping(item, $0) }
            }
        }

        if filter == .all {
            rowsByKind[.settings] = input.settings.prefix(settingsLimit).map { .setting($0) }
        }

        let sections = SearchSectionKind.allCases.compactMap { kind -> SearchSection? in
            guard let rows = rowsByKind[kind], !rows.isEmpty else { return nil }
            return SearchSection(kind: kind, rows: rows)
        }
        return SearchResults(sections: sections)
    }
}
