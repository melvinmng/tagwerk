import Foundation

/// Read cache of the last fetched issues, used when GitHub is unreachable.
@MainActor
public protocol GitHubCache: AnyObject {
    func load() -> (records: [GitHubIssueRecord], fetchedAt: Date)?
    func store(_ records: [GitHubIssueRecord], fetchedAt: Date)
}
