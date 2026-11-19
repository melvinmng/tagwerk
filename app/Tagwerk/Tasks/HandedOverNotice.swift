import Foundation
import TagwerkCore

/// What the capsule shows after an issue left the user's lists: its number, why, the people it is
/// assigned to now and the link to GitHub.
struct HandedOverNotice: Equatable, Identifiable {
    /// Why the issue is not in the lists.
    enum Reason: Equatable {
        /// It was assigned to someone else ("Vergeben").
        case handedOver
        /// It sits in no Project, so none of the lists reads it.
        case noProject
    }

    let id: TaskID
    let number: Int?
    let assignees: [String]
    let url: URL?
    let reason: Reason

    /// An issue without a placement is explained by the missing Project, even when it is assigned to
    /// others as well: that reason is certain from the item, the assignee relation needs the login.
    init(item: TaskItem) {
        id = item.id
        number = item.issueNumber
        assignees = item.assignees ?? []
        url = item.url
        reason = item.statuses.isEmpty ? .noProject : .handedOver
    }

    var title: String {
        switch reason {
        case .handedOver: AssigneeSelection.capsuleTitle(number: number, assignees: assignees)
        case .noProject: AssigneeSelection.noProjectTitle(number: number)
        }
    }

    var caption: LocalizedStringResource {
        switch reason {
        case .handedOver: "Vergeben"
        case .noProject: "Angelegt"
        }
    }

    var symbol: String {
        switch reason {
        case .handedOver: "person.crop.circle.badge.checkmark"
        case .noProject: "tray"
        }
    }

    var announcement: String {
        switch reason {
        case .handedOver: AssigneeSelection.announcement(number: number, assignees: assignees)
        case .noProject: AssigneeSelection.noProjectAnnouncement(number: number)
        }
    }
}

extension TaskItem {
    /// Issue number taken from the URL ("…/issues/151"); `nil` for tasks without a numbered URL.
    var issueNumber: Int? {
        url.flatMap { Int($0.lastPathComponent) }
    }
}
