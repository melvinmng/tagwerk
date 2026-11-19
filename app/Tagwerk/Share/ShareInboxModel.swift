import Foundation
import Observation
import TagwerkCore

extension AppGroup {
    /// `<container>/Library/Application Support/ShareInbox`; `nil` without the App Group (unsigned builds, unit tests).
    static var shareInboxDirectory: URL? {
        guard let identifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return ShareInbox.defaultDirectory(in: container)
    }
}

/// The app side of the share inbox (plan P6, task 5): decides which waiting item opens its sheet next. Reading the inbox
/// changes nothing; an item is removed only when the user confirms or discards it.
///
/// - Nothing is offered before the setup is done or while another sheet is open (`canPresent`).
/// - Items go in order, the ones offered least often first.
/// - Swiping a sheet away counts as an offer and pauses the inbox until the app becomes active again; after
///   `ShareInbox.maximumOffers` offers the item is only listed (`parked`).
@MainActor
@Observable
final class ShareInboxModel {
    /// The item whose sheet is open (or about to open).
    private(set) var current: ShareInboxItem?
    /// Items offered often enough; they appear as the row "Geteilt (n)" in "Aufgaben".
    private(set) var parked: [ShareInboxItem] = []
    /// Raised when the root view should look at the inbox again (the app became active, a sheet closed).
    private(set) var refreshRequests = 0

    @ObservationIgnored private let inbox: ShareInbox?
    @ObservationIgnored private let isSetupCompleted: @MainActor () -> Bool
    @ObservationIgnored private var isPaused = false

    init(inbox: ShareInbox?, isSetupCompleted: @escaping @MainActor () -> Bool) {
        self.inbox = inbox
        self.isSetupCompleted = isSetupCompleted
    }

    /// The app became active: items offered before may be offered again.
    func appBecameActive() {
        isPaused = false
        requestRefresh()
    }

    func requestRefresh() { refreshRequests += 1 }

    /// Reads the inbox and opens the next item when allowed. Calling it again while an item is open changes nothing.
    /// Returns `true` when an item is waiting only because another sheet is open (`canPresent == false`), so the caller
    /// can look again later.
    @discardableResult
    func refresh(canPresent: Bool = true) -> Bool {
        guard let inbox else { return false }
        let items = inbox.pending()
        parked = items.filter { $0.offeredCount >= ShareInbox.maximumOffers }
        guard current == nil, !isPaused, isSetupCompleted() else { return false }
        let next = items.filter { $0.offeredCount < ShareInbox.maximumOffers }
            .min { ($0.offeredCount, $0.createdAt, $0.id.uuidString) < ($1.offeredCount, $1.createdAt, $1.id.uuidString) }
        guard let next else { return false }
        guard canPresent else { return true }
        current = next
        return false
    }

    /// The sheet was swiped away or closed with "Abbrechen": the item stays, counted as offered.
    func dismissCurrent() {
        guard let item = current else { return }
        inbox?.markOffered(item.id)
        current = nil
        isPaused = true
        parked = (inbox?.pending() ?? []).filter { $0.offeredCount >= ShareInbox.maximumOffers }
    }

    /// The item was taken over or discarded: it goes with its files. The next item opens on the next `refresh`, after the
    /// closing sheet is gone.
    func finish(_ id: UUID) {
        inbox?.remove(id)
        if current?.id == id { current = nil }
        parked.removeAll { $0.id == id }
    }

    /// "Übernehmen" in the list of parked items: the item is offered again.
    func accept(_ id: UUID) {
        inbox?.resetOffers(id)
        isPaused = false
        parked.removeAll { $0.id == id }
        requestRefresh()
    }

    func url(for file: ShareInboxFile, in item: ShareInboxItem) -> URL? {
        inbox?.fileURL(for: file, in: item)
    }
}
