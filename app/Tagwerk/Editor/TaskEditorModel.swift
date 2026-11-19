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

    /// Fields changed at the source since opening, for the conflict card.
    var conflictChanges: [ConflictChange] {
        conflict.map { ConflictChange.changes(original: original, draft: draft, current: $0) } ?? []
    }

    /// Reminders know four levels (!!!, !!, !, none), so they offer P1–P4 without "Keine".
    var priorityChoices: [Priority?] { Self.priorityChoices(for: original.id.source) }

    static func priorityChoices(for source: TaskSource) -> [Priority?] {
        source == .reminders ? [.p1, .p2, .p3, .p4] : [nil] + Priority.allCases.map { $0 }
    }

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

    // MARK: Recurrence (plan 2026-11-18, stages 1 and 2)

    /// Only sources that can write a repetition (reminders, local tasks) show the row; GitHub issues show none.
    var showsRecurrenceRow: Bool { isVisible(.recurrence) }

    /// Sets the repetition from the recurrence page. A repetition needs a due date: without one, the due
    /// date becomes `fallbackDue` (the first occurrence), without time.
    func setRecurrence(_ recurrence: Recurrence?, fallbackDue: PlanDay) {
        draft.recurrence = recurrence
        if recurrence != nil, draft.due == nil {
            draft.due = DueDate(year: fallbackDue.year, month: fallbackDue.month, day: fallbackDue.day)
        }
    }

    /// "Fällig" on or off. Off also removes the repetition, because a repeating task needs a due date.
    func setHasDue(_ isOn: Bool, today: PlanDay) {
        if isOn {
            if draft.due == nil { draft.due = DueDate(year: today.year, month: today.month, day: today.day) }
        } else {
            draft.due = nil
            draft.recurrence = nil
        }
    }

    /// Turning "Fällig" off removed the task's repetition (shown as a hint under the toggle).
    var removesRecurrenceWithDue: Bool {
        original.recurrence != nil && draft.due == nil && draft.recurrence == nil
    }

    /// The new rule when this edit sets one (not when it removes the rule), starting at the draft's due date;
    /// planned blocks are checked against it before saving.
    var changedRecurrence: Recurrence? {
        guard case .set(var recurrence?) = TaskEdit.diff(from: original, to: draft).recurrence,
              let due = draft.due else { return nil }
        recurrence.start = PlanDay(due)
        return recurrence
    }

    /// What to ask before saving, as one step at most (risk table of the plan: never two dialogs).
    enum SaveQuestion: Equatable {
        /// The effort of a recurring reminder changed: "Nur am …" or "Für alle ab …". Blocks that end up on
        /// days without an occurrence are named in the same dialog; they stay in the calendar.
        case effortReach(blocksOffSeries: [CalendarEvent])
        /// The new rule leaves planned blocks on days without an occurrence; they stay in the calendar.
        case keepBlocks([CalendarEvent])
    }

    static func saveQuestion(effortChanged: Bool, blocksOffSeries: [CalendarEvent]) -> SaveQuestion? {
        if effortChanged { return .effortReach(blocksOffSeries: blocksOffSeries) }
        return blocksOffSeries.isEmpty ? nil : .keepBlocks(blocksOffSeries)
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
            refreshed = nil  // the saved item supersedes the state after the comment
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
