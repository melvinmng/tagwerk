import AIKit
import Foundation
import GitHubKit
import TagwerkCore

extension AppTools {
    /// Longest note title the assistant sees (decision D4).
    static let maxNoteTitleLength = 80

    /// `search`: events, tasks, notes, shopping items and, on request, GitHub issues by text.
    ///
    /// Notes come with a title (first line, at most `maxNoteTitleLength` characters) and the excerpt around the hit
    /// (at most 80 characters, decision D4). Private notes are not part of `SearchToolSources.notes`, so they are
    /// neither listed nor counted. Without the consent only the number of matching notes is reported (`notesLocked`).
    /// The text of an event or task note never leaves: an entry names the fields that matched (`matchedIn`).
    func runSearch(_ args: Arguments) async throws -> String {
        guard let search else { throw ToolError(String(localized: "Die Suche ist nicht verfügbar.")) }
        guard let query = SearchQuery(try args.require("query")) else {
            throw ToolError(String(localized: "Der Suchtext braucht mindestens zwei Zeichen."))
        }
        let filter: SearchFilter = switch args.string("kind") {
        case "events": .events
        case "tasks": .tasks
        default: .all
        }
        let calendar = planning.calendar
        let window = SearchWindow.initial(now: planning.now(), calendar: calendar)
        let start = try args.string("from").map { _ in try args.day("from").startDate(in: calendar) } ?? window.start
        let end = try args.string("to").map { _ in
            try args.day("to").adding(days: 1, calendar: calendar).startDate(in: calendar)
        } ?? window.end
        guard start < end else { throw ToolError(String(localized: "Der Zeitraum ist ungültig.")) }
        guard let limit = calendar.date(byAdding: .year, value: Self.maxSearchYears, to: start), end <= limit else {
            throw ToolError(String(localized: "Der Zeitraum darf höchstens vier Jahre umfassen."))
        }

        let includeCompleted = args.bool("include_completed") ?? false
        let fetched = filter == .tasks ? [] : await search.events(DateInterval(start: start, end: end))
        let completed = includeCompleted && filter != .events ? await search.completedTasks() : []

        // The online search sends the search text to GitHub: only on request (`github_online`), never for events only.
        var online: [OnlineIssue]?
        var onlineError: String?
        if args.bool("github_online") == true, filter != .events, let searchOnline = search.searchOnline {
            do {
                online = try await searchOnline(query.text)
            } catch {
                onlineError = Self.onlineErrorName(error)
            }
        }

        let includesNotes = filter == .all
        let input = SearchInput(events: fetched, calendarNames: search.calendarNames(),
                                openTasks: taskList.items.filter { !$0.isCompleted }, completed: completed, online: online,
                                notes: includesNotes ? search.notes() : [], shopping: includesNotes ? search.shopping() : [])
        let results = SearchResults.make(query: query, filter: filter, includeCompleted: includeCompleted, input: input,
                                         now: planning.now(), calendar: calendar)

        var eventRows: [(EventRow, SearchMatch)] = []
        var taskRows: [(item: TaskItem, completedAt: Date?, isCompleted: Bool, match: SearchMatch)] = []
        var noteRows: [(NoteSearchItem, SearchMatch)] = []
        var shoppingRows: [(ShoppingSearchItem, SearchMatch)] = []
        var issueRows: [OnlineIssue] = []
        for section in results.sections {
            for row in section.rows {
                switch row {
                case .event(let eventRow, let match): eventRows.append((eventRow, match))
                case .task(let item, let match): taskRows.append((item, nil, false, match))
                case .completed(let group, let match): taskRows.append((group.latest.item, group.latest.completedAt, true, match))
                case .note(let note, let match): noteRows.append((note, match))
                case .shopping(let item, let match): shoppingRows.append((item, match))
                case .online(let issue): issueRows.append(issue)
                // The assistant's input has no settings (it gets no settings hits by design), so this row never occurs.
                case .setting: break
                }
            }
        }
        let deadlineIDs = planning.deadlineEventIDs(among: eventRows.map(\.0.event))
        let events = eventRows.prefix(Self.maxSearchResults).map { row, match -> [String: Any] in
            var item = eventSummary(row.event, deadlineIDs: deadlineIDs)
            item["matchedIn"] = match.matchedFields.map(\.rawValue)
            if row.moreOccurrences > 0 { item["moreOccurrences"] = row.moreOccurrences }
            return item
        }
        let tasks = taskRows.prefix(Self.maxSearchResults).map { row -> [String: Any] in
            var item = Self.summary(row.item)
            item["matchedIn"] = row.match.matchedFields.map(\.rawValue)
            if row.isCompleted {
                item["completed"] = true
                if let date = row.completedAt { item["completedAt"] = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)) }
            }
            return item
        }
        var answer: [String: Any] = [
            "events": Array(events), "tasks": Array(tasks), "eventCount": eventRows.count, "taskCount": taskRows.count,
            // `end` is exclusive: the last searched day is the one before it.
            "searched": ["from": AIPlanner.dayString(PlanDay(date: start, calendar: calendar)),
                         "to": args.string("to") ?? AIPlanner.dayString(
                            PlanDay(date: calendar.date(byAdding: .day, value: -1, to: end) ?? end, calendar: calendar))],
        ]
        // Without calendar access an empty event list would read as "nothing found".
        if filter != .tasks, fetched == nil { answer["calendarAccess"] = false }

        if includesNotes {
            answer["noteCount"] = noteRows.count
            if search.notesAllowed() {
                answer["notes"] = noteRows.prefix(Self.maxSearchResults).map { Self.noteEntry($0.0, match: $0.1, calendar: calendar) }
            } else {
                answer["notesLocked"] = true
            }
            answer["shopping"] = shoppingRows.prefix(Self.maxSearchResults).map { row -> [String: Any] in
                var item: [String: Any] = ["id": row.0.id, "name": row.0.name, "matchedIn": row.1.matchedFields.map(\.rawValue)]
                if let quantity = row.0.quantity { item["quantity"] = quantity }
                return item
            }
            answer["shoppingCount"] = shoppingRows.count
        }
        if let onlineError {
            answer["githubError"] = onlineError
        } else if let online {
            answer["issues"] = issueRows.prefix(Self.maxSearchResults).map(Self.issueEntry)
            // The ids in the answer stay valid for a following assign_task.
            rememberFoundIssues(online)
        }
        return Self.json(answer)
    }

    /// One note hit: id, title, kind, dates and the excerpt around the hit. The excerpt is empty when the title matches.
    static func noteEntry(_ note: NoteSearchItem, match: SearchMatch, calendar: Calendar) -> [String: Any] {
        let title = SearchDocument(noteText: note.text, kindLabel: note.kindLabel).title
        var entry: [String: Any] = [
            "id": NoteToolAccess.key(for: note.id), "title": truncated(title, to: maxNoteTitleLength), "kind": note.kindLabel,
            "updated": AIPlanner.dayString(PlanDay(date: note.updatedAt, calendar: calendar)),
            "matchedIn": match.matchedFields.map(\.rawValue),
        ]
        if let day = note.dayKey { entry["day"] = day }
        if let snippet = match.snippet?.text { entry["snippet"] = snippet }
        return entry
    }

    /// At most `limit` characters; a longer text ends with "…".
    static func truncated(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    static func issueEntry(_ issue: OnlineIssue) -> [String: Any] {
        let state: String = switch issue.marker {
        case .closed?: "closed"
        case .unassigned?: "unassigned"
        case .assignedToOthers?: "assigned_to_others"
        case .noProject?: "no_project"
        case nil: "open"
        }
        return ["id": TaskID(source: .github, rawValue: issue.id).key, "number": issue.number, "title": issue.title, "repository": issue.repository,
                "url": issue.url.absoluteString, "state": state, "assignees": issue.assignees]
    }

    /// A short name for a failed online search; never the text of the error.
    static func onlineErrorName(_ error: Error) -> String {
        switch error as? IssueSearchError {
        case .offline?: "offline"
        case .rateLimited?: "rate_limited"
        case .signedOut?: "signed_out"
        default: "failed"
        }
    }

    // MARK: Stored form

    /// Removes title and snippet from the note entries of a `search` output and marks each as `"redacted": true`; ids,
    /// kind, dates, `matchedIn` and all counts stay (session rule: note text is not kept in a stored chat). An output
    /// without note entries is returned unchanged. An output that is cut in the middle (`Conversation.clipped`) cannot
    /// be parsed; if it holds note entries anyway it is replaced by a short marker, so no title is ever kept.
    static func redactedSearchOutput(_ output: String) -> String {
        guard let data = output.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return output.contains("\"id\":\"\(NoteToolAccess.keyPrefix)") ? #"{"ok":true,"redacted":true}"# : output
        }
        guard let notes = object["notes"] as? [[String: Any]] else { return output }
        object["notes"] = notes.map { entry -> [String: Any] in
            var kept = entry
            kept["title"] = nil
            kept["snippet"] = nil
            kept["redacted"] = true
            return kept
        }
        return json(object)
    }
}
