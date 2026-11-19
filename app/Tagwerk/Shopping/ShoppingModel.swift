import Foundation
import Observation
import RemindersKit
import TagwerkCore

/// The shopping list: the reminders of the list chosen in the settings. The only place that reads and writes
/// its items; the page, the entry row, the assistant and the shortcut all use it. Items are never stored
/// locally, Apple Reminders stays the source of truth.
@MainActor
@Observable
final class ShoppingModel {
    enum State: Equatable {
        /// No list chosen.
        case noList
        /// The chosen list no longer exists in Reminders.
        case listMissing
        /// No full access to Reminders.
        case accessDenied
        case ready
    }

    /// Result of adding items; each list holds item names.
    struct AddReport: Equatable {
        var added: [String] = []
        var reopened: [String] = []
        var alreadyOnList: [String] = []
        /// Names that could not be written.
        var failed: [String] = []
        /// Text of the first failure.
        var errorMessage: String?
    }

    /// "Erledigt" shows items completed within this time before now.
    static let completedWindow: TimeInterval = 7 * 24 * 3600
    /// Names of items completed within this time before now are offered to Siri as article names.
    static let historyWindow: TimeInterval = 180 * 24 * 3600

    @ObservationIgnored private let store: any ReminderStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let categories: ShoppingCategoryStore
    @ObservationIgnored private let dictionary: ShoppingDictionary
    @ObservationIgnored private let now: () -> Date

    private(set) var state: State = .noList
    private(set) var listTitle: String?
    /// Open items in the order of the sections.
    private(set) var openItems: [ShoppingItem] = []
    /// Items completed within `completedWindow`, newest first.
    private(set) var completedItems: [ShoppingItem] = []
    private(set) var sections: [ShoppingSection] = []

    /// Called when the set of item names seen by `reload()` changed (first load included), so Siri can learn
    /// the new names. Not called when only quantities or the order changed.
    @ObservationIgnored var onNamesChanged: (() -> Void)?
    @ObservationIgnored private var nameSignature: Set<String>?

    @ObservationIgnored private var openRecords: [ReminderRecord] = []
    @ObservationIgnored private var completedRecords: [ReminderRecord] = []

    init(store: any ReminderStore, settings: AppSettings, categories: ShoppingCategoryStore,
         dictionary: ShoppingDictionary = .bundled, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.settings = settings
        self.categories = categories
        self.dictionary = dictionary
        self.now = now
    }

    // MARK: Loading

    func reload() async {
        guard store.accessState == .fullAccess else { return clear(.accessDenied) }
        guard let listID = settings.shoppingListID else { return clear(.noList) }
        guard let list = store.lists().first(where: { $0.id == listID }) else { return clear(.listMissing) }
        let current = now()
        // The end lies slightly ahead, so an item completed this very moment is not cut off by clock rounding.
        let window = DateInterval(start: current.addingTimeInterval(-Self.completedWindow), end: current.addingTimeInterval(60))
        openRecords = await store.openReminders(in: [listID])
        completedRecords = await store.completedReminders(in: window, listIDs: [listID])
            .sorted { ($0.completedAt ?? .distantPast, $0.id) > ($1.completedAt ?? .distantPast, $1.id) }
        state = .ready
        listTitle = list.title
        completedItems = completedRecords.map(Self.item)
        refreshSections()
        notifyIfNamesChanged()
    }

    /// Open and completed items of the shopping list with the date they were last touched; the source of the
    /// names Siri can speak. Reads further back than `completedItems`. Empty without access or list.
    func history() async -> [ShoppingHistoryEntry] {
        guard store.accessState == .fullAccess, let listID = settings.shoppingListID,
              store.lists().contains(where: { $0.id == listID }) else { return [] }
        let current = now()
        let window = DateInterval(start: current.addingTimeInterval(-Self.historyWindow), end: current.addingTimeInterval(60))
        let open = await store.openReminders(in: [listID])
        let completed = await store.completedReminders(in: window, listIDs: [listID])
        return (open + completed).map { record in
            ShoppingHistoryEntry(name: record.title, date: [record.completedAt, record.createdAt].compactMap { $0 }.max())
        }
    }

    private func notifyIfNamesChanged() {
        let signature = Set((openRecords + completedRecords).map { ShoppingName.key($0.title) })
        guard signature != nameSignature else { return }
        nameSignature = signature
        onNamesChanged?()
    }

    /// Sorts the open items into sections again, e.g. after categories or assignments changed.
    func refreshSections() {
        sections = ShoppingSections.make(open: openRecords.map(Self.item), assignments: categories.assignments(),
                                         categories: categories.categories(), dictionary: dictionary)
        openItems = sections.flatMap(\.items)
    }

    /// The category the item is shown under; `nil` is "Sonstiges".
    func categoryID(of item: ShoppingItem) -> UUID? {
        ShoppingClassifier.categoryID(forKey: ShoppingName.key(item.name), assignments: categories.assignments(),
                                      categories: categories.categories(), dictionary: dictionary)
    }

    /// Name of the category the item is shown under; `nil` is "Sonstiges".
    func categoryName(of item: ShoppingItem) -> String? {
        guard let id = categoryID(of: item) else { return nil }
        return categories.categories().first { $0.id == id }?.name
    }

    /// Category name of every open item that has one, read from the sections already sorted and one fetch of the
    /// categories; items in "Sonstiges" are missing.
    func categoryNamesByItemID() -> [String: String] {
        let names = Dictionary(categories.categories().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var result: [String: String] = [:]
        for section in sections {
            guard let id = section.categoryID, let name = names[id] else { continue }
            for item in section.items { result[item.id] = name }
        }
        return result
    }

    private func clear(_ newState: State) {
        state = newState
        listTitle = nil
        openRecords = []
        completedRecords = []
        openItems = []
        completedItems = []
        sections = []
        notifyIfNamesChanged()
    }

    private static func item(_ record: ReminderRecord) -> ShoppingItem {
        let notes = ShoppingItem.quantity(fromNotes: record.notes)
        return ShoppingItem(id: record.id, name: record.title, quantity: notes.quantity, isCompleted: record.isCompleted,
                            completedAt: record.completedAt, createdAt: record.createdAt, hasLongNotes: notes.hasLongNotes)
    }

    // MARK: Adding

    /// Adds items without creating duplicates: an open item of the same name stays (a given quantity replaces
    /// its quantity), a recently completed one is reopened, anything else becomes a new plain reminder.
    /// A caller that loaded the list just before passes `reloadFirst: false` to save the second read.
    func add(_ items: [ParsedItem], reloadFirst: Bool = true) async -> AddReport {
        if reloadFirst { await reload() }
        var report = AddReport()
        guard state == .ready, let listID = settings.shoppingListID else {
            report.failed = items.map(\.name)
            report.errorMessage = state == .accessDenied
                ? TaskListModel.message(for: TaskWriteError.accessDenied)
                : String(localized: "Es ist keine Einkaufsliste eingerichtet.")
            return report
        }
        // The loaded state is carried along item by item, so a name given twice in one input is created once.
        var open = Dictionary(openRecords.map { (ShoppingName.key($0.title), $0) }, uniquingKeysWith: { first, _ in first })
        var completed = Dictionary(completedRecords.map { (ShoppingName.key($0.title), $0) }, uniquingKeysWith: { first, _ in first })
        for item in items {
            let key = ShoppingName.key(item.name)
            guard !key.isEmpty else { continue }
            do {
                if let existing = open[key] {
                    open[key] = try settingQuantity(item.quantity, on: existing, reopening: false)
                    report.alreadyOnList.append(existing.title)
                } else if let existing = completed[key] {
                    open[key] = try settingQuantity(item.quantity, on: existing, reopening: true)
                    completed[key] = nil
                    report.reopened.append(existing.title)
                } else {
                    open[key] = try store.create(title: item.name, notes: item.quantity, due: nil, ekPriority: 0, listID: listID,
                                                 recurrence: nil)
                    report.added.append(item.name)
                }
            } catch {
                report.failed.append(item.name)
                if report.errorMessage == nil { report.errorMessage = TaskListModel.message(for: error) }
            }
        }
        await reload()
        return report
    }

    /// Saves only when something changes. Notes with more than the quantity line are never overwritten.
    private func settingQuantity(_ quantity: String?, on record: ReminderRecord, reopening: Bool) throws -> ReminderRecord {
        var changed = record
        if reopening { changed.isCompleted = false }
        if let quantity, !ShoppingItem.quantity(fromNotes: record.notes).hasLongNotes { changed.notes = quantity }
        guard changed != record else { return record }
        return try store.save(changed, recurrence: .unchanged)
    }

    // MARK: Changing

    /// Marks the item completed; it is never deleted by this.
    func checkOff(id: String) async throws {
        var record = try shoppingRecord(id)
        record.isCompleted = true
        _ = try store.save(record, recurrence: .unchanged)
        await reload()
    }

    /// Result of checking off several items; names for the items that were checked off, ids for the others.
    struct CheckOffReport: Equatable {
        var checkedOff: [String] = []
        var notFound: [String] = []
    }

    /// Checks off several items: every item is saved, then the list is read once. An id outside the shopping list
    /// or a failed write lands in `notFound` and does not stop the rest.
    func checkOff(ids: [String]) async -> CheckOffReport {
        var report = CheckOffReport()
        for id in ids {
            do {
                var record = try shoppingRecord(id)
                record.isCompleted = true
                _ = try store.save(record, recurrence: .unchanged)
                report.checkedOff.append(record.title)
            } catch {
                report.notFound.append(id)
            }
        }
        if !ids.isEmpty { await reload() }
        return report
    }

    func reopen(id: String) async throws {
        var record = try shoppingRecord(id)
        record.isCompleted = false
        _ = try store.save(record, recurrence: .unchanged)
        await reload()
    }

    /// Renames the item and sets its quantity. The quantity is ignored when the notes hold more than one line.
    func update(id: String, name: String, quantity: String?) async throws {
        var record = try shoppingRecord(id)
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ShoppingInputParser.maxNameLength))
        if !trimmedName.isEmpty { record.title = trimmedName }
        if !ShoppingItem.quantity(fromNotes: record.notes).hasLongNotes {
            let trimmedQuantity = quantity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            record.notes = trimmedQuantity.isEmpty ? nil : trimmedQuantity
        }
        _ = try store.save(record, recurrence: .unchanged)
        await reload()
    }

    func delete(id: String) async throws {
        _ = try shoppingRecord(id)
        try store.delete(id: id)
        await reload()
    }

    /// Deletes exactly the items shown under "Erledigt"; older completed ones stay in Reminders.
    /// Returns the number of deleted items.
    @discardableResult
    func removeCompleted() async -> Int {
        var deleted = 0
        for item in completedItems {
            guard let record = try? shoppingRecord(item.id), record.isCompleted else { continue }
            if (try? store.delete(id: item.id)) != nil { deleted += 1 }
        }
        await reload()
        return deleted
    }

    /// Remembers the category for the item's name; it then applies to every item of that name.
    func setCategory(_ categoryID: UUID?, forItemID id: String) {
        guard let item = (openItems + completedItems).first(where: { $0.id == id }) else { return }
        categories.assign(nameKey: ShoppingName.key(item.name), to: categoryID, manual: true)
        refreshSections()
    }

    /// The fresh reminder, but only if it lies in the shopping list: no write of this model may reach another list.
    private func shoppingRecord(_ id: String) throws -> ReminderRecord {
        guard store.accessState == .fullAccess else { throw TaskWriteError.accessDenied }
        guard let listID = settings.shoppingListID, let record = store.reminder(id: id), record.listID == listID else {
            throw TaskWriteError.notFound
        }
        return record
    }
}
