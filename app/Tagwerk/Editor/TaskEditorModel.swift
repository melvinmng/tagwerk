import Foundation
import Observation
import TagwerkCore

/// Edit state of one task with conflict protection (mockup 3).
@MainActor
@Observable
final class TaskEditorModel {
    var draft: TaskItem
    private(set) var original: TaskItem
    /// Fresh state from the source after a version mismatch; drives the conflict banner.
    private(set) var conflict: TaskItem?
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    /// Result of the last successful save, handed back to the list.
    private(set) var saved: TaskItem?

    /// Projects that field changes apply to (GitHub issues in several projects); default: all.
    var targetProjects: Set<String>
    var comment = ""

    private let provider: any TaskProvider
    /// Fresh state after the user's own comment; handed to the list when the sheet closes.
    private(set) var refreshed: TaskItem?
    private(set) var isPostingComment = false

    /// Posts a comment for (task, text, expected version); returns the fresh item when nothing else changed.
    typealias CommentAction = (TaskID, String, String) async throws -> TaskItem?
    private let addComment: CommentAction?

    init(item: TaskItem, provider: any TaskProvider, addComment: CommentAction? = nil) {
        self.draft = item
        self.original = item
        self.provider = provider
        self.addComment = addComment
        self.targetProjects = Set(item.subContainers.map(\.id))
    }

    var canComment: Bool { addComment != nil }

    /// GitHub's "Due date" field holds a date only.
    var supportsDueTime: Bool { original.id.source != .github }

    func postComment() async {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let addComment, !text.isEmpty, !isPostingComment else { return }
        isPostingComment = true
        defer { isPostingComment = false }
        do {
            if let fresh = try await addComment(original.id, text, original.version) {
                // Only our own comment changed the issue: keep the user's edits, adopt the new version.
                original.version = fresh.version
                draft.version = fresh.version
                refreshed = fresh
            }
            comment = ""
            errorMessage = nil
        } catch {
            errorMessage = TaskListModel.message(for: error)
        }
    }

    var hasChanges: Bool { !TaskEdit.diff(from: original, to: draft).isEmpty }

    func isVisible(_ field: TaskField) -> Bool {
        original.editableFields.contains(field)
    }

    /// Saves the user's changes if the source is unchanged. Returns `true` when the sheet can close.
    func save() async -> Bool {
        await write(expectedVersion: original.version)
    }

    /// "Trotzdem sichern": writes only the user's own changes, ignoring the newer version.
    func saveAnyway() async -> Bool {
        await write(expectedVersion: nil)
    }

    /// "Neu laden": discards the user's changes and shows the current state of the source.
    func reloadFromSource() async {
        do {
            let current = try await provider.task(id: original.id) ?? conflict ?? original
            original = current
            draft = current
            targetProjects = Set(current.subContainers.map(\.id))
            conflict = nil
            errorMessage = nil
        } catch {
            errorMessage = TaskListModel.message(for: error)
        }
    }

    private func write(expectedVersion: String?) async -> Bool {
        var edit = TaskEdit.diff(from: original, to: draft)
        guard !edit.isEmpty else { return true }
        let allProjects = Set(original.subContainers.map(\.id))
        if !targetProjects.isEmpty, targetProjects != allProjects { edit.targetSubContainerIDs = targetProjects }
        isSaving = true
        defer { isSaving = false }
        do {
            saved = try await provider.apply(edit, to: original.id, expectedVersion: expectedVersion)
            conflict = nil
            errorMessage = nil
            return true
        } catch TaskWriteError.conflict(let current) {
            conflict = current
            return false
        } catch {
            errorMessage = TaskListModel.message(for: error)
            return false
        }
    }
}
