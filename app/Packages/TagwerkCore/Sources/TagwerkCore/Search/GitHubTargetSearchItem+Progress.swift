import Foundation

extension GitHubTargetSearchItem {
    /// The project of the project progress (#332) that a tap on the hit opens. A repository is shown with its full name, because
    /// the name alone is not unique across owners.
    public var progressReference: ProjectProgressReference {
        switch kind {
        case .repository: ProjectProgressReference(kind: .gitHubRepository, id: targetID, title: targetID)
        case .project: ProjectProgressReference(kind: .gitHubProject, id: targetID, title: title)
        }
    }
}
