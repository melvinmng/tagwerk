import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The model with a real inbox in a temporary folder and invented items.
@MainActor
final class ShareInboxImporterTests {
    private let root: URL
    private let inbox: ShareInbox
    private var setupCompleted = true
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "ShareInboxImporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        inbox = ShareInbox(directory: root.appending(path: "inbox", directoryHint: .isDirectory))
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private func makeModel() -> ShareInboxModel {
        ShareInboxModel(inbox: inbox, isSetupCompleted: { [unowned self] in setupCompleted })
    }

    @discardableResult
    private func put(_ title: String, target: ShareTarget = .task) throws -> ShareInboxItem {
        clock = clock.addingTimeInterval(1)
        return try inbox.write(ShareInboxItem(createdAt: clock, target: target, title: title))
    }

    @Test func threeItems_areOfferedInOrder() throws {
        let model = makeModel()
        try put("eins")
        try put("zwei")
        try put("drei")
        model.refresh()
        #expect(model.current?.title == "eins")
        model.finish(try #require(model.current?.id))
        #expect(model.current == nil)
        model.refresh()
        #expect(model.current?.title == "zwei")
        model.finish(try #require(model.current?.id))
        model.refresh()
        #expect(model.current?.title == "drei")
        model.finish(try #require(model.current?.id))
        model.refresh()
        #expect(model.current == nil)
        #expect(inbox.pending().isEmpty)
    }

    @Test func reactivation_doesNotOfferTheSameItemTwice() throws {
        let model = makeModel()
        try put("eins")
        try put("zwei")
        model.refresh()
        let first = try #require(model.current)
        // The app becomes active again while the sheet is open.
        model.appBecameActive()
        model.refresh()
        model.refresh()
        #expect(model.current == first)
        model.finish(first.id)
        model.refresh()
        #expect(model.current?.title == "zwei")
    }

    @Test func dismissedItem_isOfferedAgainAtMostThreeTimes() throws {
        let model = makeModel()
        let item = try put("bleibt")
        for round in 1...ShareInbox.maximumOffers {
            model.appBecameActive()
            model.refresh()
            #expect(model.current?.id == item.id, "offer \(round)")
            model.dismissCurrent()
            #expect(model.current == nil)
            // Without a new activation the inbox stays quiet.
            model.refresh()
            #expect(model.current == nil)
        }
        model.appBecameActive()
        model.refresh()
        #expect(model.current == nil)
        #expect(model.parked.map(\.id) == [item.id])
        #expect(inbox.pending().count == 1)
    }

    @Test func dismissedItem_comesAfterItemsNeverOffered() throws {
        let model = makeModel()
        try put("alt")
        model.refresh()
        model.dismissCurrent()
        try put("neu")
        model.appBecameActive()
        model.refresh()
        #expect(model.current?.title == "neu")
    }

    @Test func nothingBeforeSetup() throws {
        setupCompleted = false
        let model = makeModel()
        try put("wartet")
        model.refresh()
        #expect(model.current == nil)
        setupCompleted = true
        model.refresh()
        #expect(model.current?.title == "wartet")
    }

    @Test func nothingWhileAnotherSheetIsOpen() throws {
        let model = makeModel()
        try put("wartet")
        model.refresh(canPresent: false)
        #expect(model.current == nil)
        model.refresh(canPresent: true)
        #expect(model.current?.title == "wartet")
    }

    @Test func finish_removesFiles() throws {
        let model = makeModel()
        let source = root.appending(path: "bild.png")
        try Data(repeating: 1, count: 10).write(to: source)
        let stored = try inbox.write(ShareInboxItem(createdAt: clock, target: .note, title: "Bild"),
                                     copying: [ShareInboxSource(url: source, name: "bild.png", typeIdentifier: "public.png")])
        model.refresh()
        let item = try #require(model.current)
        let file = try #require(item.files.first)
        #expect(model.url(for: file, in: item) != nil)
        model.finish(stored.id)
        #expect(model.url(for: file, in: item) == nil)
        #expect(inbox.pending().isEmpty)
    }

    @Test func parkedItems_areListedAndCanBeRemoved() throws {
        let model = makeModel()
        let parked = try put("geparkt")
        for _ in 0..<ShareInbox.maximumOffers { inbox.markOffered(parked.id) }
        let fresh = try put("frisch")
        model.refresh()
        #expect(model.parked.map(\.id) == [parked.id])
        #expect(model.current?.id == fresh.id)
        model.finish(parked.id)
        #expect(model.parked.isEmpty)
        #expect(inbox.pending().map(\.id) == [fresh.id])
    }

    @Test func accept_offersAParkedItemAgain() throws {
        let model = makeModel()
        let parked = try put("geparkt")
        for _ in 0..<ShareInbox.maximumOffers { inbox.markOffered(parked.id) }
        model.refresh()
        #expect(model.current == nil)
        model.accept(parked.id)
        model.refresh()
        #expect(model.current?.id == parked.id)
        #expect(model.parked.isEmpty)
    }

    @Test func withoutInbox_nothingHappens() {
        let model = ShareInboxModel(inbox: nil, isSetupCompleted: { true })
        model.refresh()
        #expect(model.current == nil)
        #expect(model.parked.isEmpty)
    }
}
