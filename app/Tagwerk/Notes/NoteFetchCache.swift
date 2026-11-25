import Foundation
import OSLog
import SwiftData

/// The records of one model type as the store last read them (#310). Reading every note, folder and session on each call, several
/// times per render and per keystroke of the editor, made the notes slow. The cache holds the last fetch until something saved or
/// the context has changes that are not saved yet; then the next call reads the store again.
///
/// A failed read returns the last known records instead of an empty list, so a page that follows a record does not take a failed
/// read for a deleted record.
@MainActor
final class NoteFetchCache<Model: PersistentModel> {
    private var values: [Model] = []
    private var isValid = false
    private let logger = Logger(subsystem: "local.tagwerk", category: "notes-store")
    /// How many times the store was read; the tests count them.
    private(set) var fetchCount = 0

    /// The next call reads the store again.
    func invalidate() { isValid = false }

    func fetch(in context: ModelContext) -> [Model] {
        // Unsaved changes (an insert or a delete that has not been saved) are not part of the last fetch.
        if isValid, !context.hasChanges { return values }
        fetchCount += 1
        do {
            let fetched = try context.fetch(FetchDescriptor<Model>())
            values = fetched
            isValid = !context.hasChanges
            return fetched
        } catch {
            logger.error("Fetch failed, the last known records stay: \(String(describing: error), privacy: .public)")
            return values
        }
    }
}
