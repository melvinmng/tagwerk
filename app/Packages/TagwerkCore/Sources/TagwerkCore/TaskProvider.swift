import Foundation

/// Errors a source reports when reading or writing a task.
public enum TaskWriteError: Error, Equatable, Sendable {
    /// The task changed since it was loaded; `current` is the fresh state.
    case conflict(current: TaskItem)
    case notFound
    case accessDenied
    /// The sign-in of the source ended (e.g. expired or revoked); the user must sign in again.
    case signedOut
    /// The source is only available from its offline cache; writing is blocked.
    case offline
    case failed(String)
}

/// Common interface of all task sources (Reminders, GitHub, local tasks).
@MainActor
public protocol TaskProvider: AnyObject {
    var source: TaskSource { get }
    func openTasks() async throws -> [TaskItem]
    func task(id: TaskID) async throws -> TaskItem?
    func containers() async throws -> [TaskContainer]
    /// Applies `edit`. With `expectedVersion` set, throws `.conflict` when the source changed;
    /// `nil` writes regardless ("Trotzdem sichern").
    func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem
    func create(_ draft: TaskDraft) async throws -> TaskItem
    /// Removes the task after a version check (`nil` skips the check). Sources that cannot delete
    /// (GitHub) close the task instead.
    func delete(_ id: TaskID, expectedVersion: String?) async throws
    /// Time of the cached data when the source could only be read offline; `nil` when live.
    var offlineSince: Date? { get }
    /// Why the cache is shown when it is not a connection problem (e.g. a server error); else `nil`.
    var offlineReason: String? { get }
    /// Last known tasks, shown at once while `openTasks` is still running (e.g. GitHub at app start).
    var cachedTasks: [TaskItem] { get }
    /// Adds a comment; only sources with comments (GitHub) support it.
    func addComment(_ body: String, to id: TaskID) async throws
    /// Whether a task that was just written still belongs to the user's lists.
    /// GitHub answers `false` for an issue the user is no longer assigned to.
    func isListed(_ item: TaskItem) -> Bool
}

extension TaskProvider {
    public func addComment(_ body: String, to id: TaskID) async throws {
        throw TaskWriteError.failed(String(localized: "Kommentare gibt es nur bei GitHub-Issues.", bundle: .module))
    }

    public func isListed(_ item: TaskItem) -> Bool { true }

    public var offlineSince: Date? { nil }
    public var offlineReason: String? { nil }
    public var cachedTasks: [TaskItem] { [] }
}
