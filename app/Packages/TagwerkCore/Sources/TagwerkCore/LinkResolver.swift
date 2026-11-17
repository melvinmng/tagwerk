import Foundation

public enum LinkOrigin: String, Sendable, Hashable, Codable {
    /// Tagwerk's own block (`tagwerk://` in the event's URL field).
    case url
    case manual
    /// Detected from `#<number>` or an exactly matching title.
    case automatic
}

public struct ResolvedLink: Sendable, Hashable {
    public let eventID: String
    public let taskID: TaskID
    public let origin: LinkOrigin

    public init(eventID: String, taskID: TaskID, origin: LinkOrigin) {
        self.eventID = eventID
        self.taskID = taskID
        self.origin = origin
    }
}

/// Links calendar events to tasks in the order of design §6.4: URL field, manual link, then an
/// unambiguous `#<number>` of a GitHub issue or an exactly matching reminder/local title.
public func resolveLinks(events: [CalendarEvent], tasks: [TaskItem], manual: [String: TaskID]) -> [ResolvedLink] {
    var issuesByNumber: [Int: [TaskID]] = [:]
    var titles: [String: [TaskID]] = [:]
    for task in tasks {
        if task.id.source == .github, let number = issueNumber(task) {
            issuesByNumber[number, default: []].append(task.id)
        } else if task.id.source != .github {
            titles[normalizedTitle(task.title), default: []].append(task.id)
        }
    }
    return events.compactMap { event in
        if let url = event.url, let id = TaskLinkURL.parse(url) {
            return ResolvedLink(eventID: event.id, taskID: id, origin: .url)
        }
        if let id = manual[event.id] {
            return ResolvedLink(eventID: event.id, taskID: id, origin: .manual)
        }
        if let number = referencedIssueNumber(in: event.title), let matches = issuesByNumber[number], matches.count == 1 {
            return ResolvedLink(eventID: event.id, taskID: matches[0], origin: .automatic)
        }
        if let matches = titles[normalizedTitle(event.title)], matches.count == 1 {
            return ResolvedLink(eventID: event.id, taskID: matches[0], origin: .automatic)
        }
        return nil
    }
}

private func issueNumber(_ task: TaskItem) -> Int? {
    task.url.flatMap { Int($0.lastPathComponent) }
}

/// The number after the first "#" that is followed by digits.
private func referencedIssueNumber(in title: String) -> Int? {
    guard let range = title.range(of: #"#(\d+)"#, options: .regularExpression) else { return nil }
    return Int(title[range].dropFirst())
}

func normalizedTitle(_ title: String) -> String {
    title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
