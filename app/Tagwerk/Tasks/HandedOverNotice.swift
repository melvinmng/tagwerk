import Foundation
import TagwerkCore

/// What the capsule shows after an issue left the user's lists: its number, why, the people it is
/// assigned to now and the link to GitHub.
struct HandedOverNotice: Equatable, Identifiable {
    let id: TaskID
    let number: Int?
    let assignees: [String]
    let url: URL?
    /// Why the issue is not in the lists; the provider decides.
    let reason: UnlistedReason

    init(item: TaskItem, reason: UnlistedReason) {
        id = item.id
        number = item.issueNumber
        assignees = item.assignees ?? []
        url = item.url
        self.reason = reason
    }

    var title: String {
        switch reason {
        case .handedOver: AssigneeSelection.capsuleTitle(number: number, assignees: assignees)
        case .noProject(let others): AssigneeSelection.noProjectTitle(number: number, others: others)
        case .doneInSelection(_, let openIn): AssigneeSelection.openElsewhereTitle(number: number, openIn: openIn)
        }
    }

    var caption: LocalizedStringResource {
        switch reason {
        case .handedOver: "Vergeben"
        case .noProject: "Angelegt · nicht in Aufgaben"
        case .doneInSelection(let doneIn, _):
            doneIn.count == 1 ? LocalizedStringResource("In „\(doneIn[0])“ erledigt") : LocalizedStringResource("In \(doneIn.count) Projekten erledigt")
        }
    }

    var symbol: String {
        switch reason {
        case .handedOver: "person.crop.circle.badge.checkmark"
        case .noProject: "tray"
        case .doneInSelection: "checkmark.circle"
        }
    }

    var announcement: String {
        switch reason {
        case .handedOver: AssigneeSelection.announcement(number: number, assignees: assignees)
        case .noProject(let others): AssigneeSelection.noProjectAnnouncement(number: number, others: others)
        case .doneInSelection(let doneIn, let openIn):
            AssigneeSelection.doneInSelectionAnnouncement(doneIn: doneIn, number: number, openIn: openIn)
        }
    }
}

extension TaskItem {
    /// Issue number taken from the URL ("…/issues/151"); `nil` for tasks without a numbered URL.
    var issueNumber: Int? {
        url.flatMap { Int($0.lastPathComponent) }
    }
}
