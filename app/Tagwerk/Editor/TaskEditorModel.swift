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

    private let provider: any TaskProvider

    init(item: TaskItem, provider: any TaskProvider) {
        self.draft = item
        self.original = item
        self.provider = provider
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
            conflict = nil
            errorMessage = nil
        } catch {
            errorMessage = TaskListModel.message(for: error)
        }
    }

    private func write(expectedVersion: String?) async -> Bool {
        let edit = TaskEdit.diff(from: original, to: draft)
        guard !edit.isEmpty else { return true }
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
