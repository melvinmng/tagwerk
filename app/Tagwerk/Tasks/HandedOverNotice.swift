import Foundation
import TagwerkCore

/// What the "Vergeben" capsule shows after an issue left the user's lists: its number, the people
/// it is assigned to now and the link to GitHub.
struct HandedOverNotice: Equatable, Identifiable {
    let id: TaskID
    let number: Int?
    let assignees: [String]
    let url: URL?

    init(item: TaskItem) {
        id = item.id
        number = item.issueNumber
        assignees = item.assignees ?? []
        url = item.url
    }
}

extension TaskItem {
    /// Issue number taken from the URL ("…/issues/151"); `nil` for tasks without a numbered URL.
    var issueNumber: Int? {
        url.flatMap { Int($0.lastPathComponent) }
    }
}
