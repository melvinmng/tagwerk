/// Errors a source reports when reading or writing a task.
public enum TaskWriteError: Error, Equatable, Sendable {
    /// The task changed since it was loaded; `current` is the fresh state.
    case conflict(current: TaskItem)
    case notFound
    case accessDenied
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
}
