import Foundation
import Testing
@testable import TagwerkCore

/// All tests use a temporary folder and invented data.
final class ShareInboxTests {
    private let root: URL
    private let inboxDirectory: URL
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShareInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        inboxDirectory = root.appending(path: "inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private func makeInbox() -> ShareInbox {
        ShareInbox(directory: inboxDirectory, now: { [unowned self] in clock })
    }

    private func item(_ title: String, at date: Date? = nil, target: ShareTarget = .task) -> ShareInboxItem {
        ShareInboxItem(createdAt: date ?? clock, target: target, title: title)
    }

    private func makeSourceFile(_ name: String, bytes: Int = 16) throws -> URL {
        let url = root.appending(path: name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    @Test func writeThenPending_roundTrips() throws {
        let inbox = makeInbox()
        var written = item("Seite lesen")
        written.text = "Notiz"
        written.url = URL(string: "https://example.com/a")
        written.mail = MailMessage(subject: "Hallo", senderName: "Erika Muster", messageID: "abc@example.com", bodyText: "Text")
        try inbox.write(written)
        #expect(inbox.pending() == [written])
    }

    @Test func pageTitle_roundTrips_andItemsWithoutOneStillDecode() throws {
        let inbox = makeInbox()
        var written = item("Seite")
        written.url = URL(string: "https://example.com/a")
        written.pageTitle = "Guter Artikel"
        try inbox.write(written)
        #expect(inbox.pending().first?.pageTitle == "Guter Artikel")
        // An item written before the field existed has no such key.
        let encoded = try JSONEncoder().encode(item("alt"))
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "pageTitle")
        let old = try JSONDecoder().decode(ShareInboxItem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.pageTitle == nil && old.title == "alt")
    }

    @Test func pending_sortsByCreation() throws {
        let inbox = makeInbox()
        try inbox.write(item("zweite", at: clock.addingTimeInterval(-10)))
        try inbox.write(item("dritte", at: clock.addingTimeInterval(-5)))
        try inbox.write(item("erste", at: clock.addingTimeInterval(-20)))
        #expect(inbox.pending().map(\.title) == ["erste", "zweite", "dritte"])
    }

    @Test func oldItems_areDropped() throws {
        let inbox = makeInbox()
        let old = item("alt", at: clock.addingTimeInterval(-15 * 24 * 3600))
        try inbox.write(old, copying: [ShareInboxSource(url: try makeSourceFile("a.txt"), name: "a.txt", typeIdentifier: "public.plain-text")])
        try inbox.write(item("frisch"))
        #expect(inbox.pending().map(\.title) == ["frisch"])
        #expect(!FileManager.default.fileExists(atPath: inboxDirectory.appending(path: old.id.uuidString).path))
        #expect(!FileManager.default.fileExists(atPath: inboxDirectory.appending(path: "\(old.id.uuidString).json").path))
    }

    @Test func unknownVersion_isDropped() throws {
        let inbox = makeInbox()
        var future = item("neu")
        future.version = ShareInboxItem.currentVersion + 1
        try inbox.write(future)
        try Data("not json".utf8).write(to: inboxDirectory.appending(path: "\(UUID().uuidString).json"))
        try inbox.write(item("gut"))
        #expect(inbox.pending().map(\.title) == ["gut"])
        // The broken files are gone, not just skipped.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: inboxDirectory.path)
        #expect(remaining.count == 1)
    }

    @Test func full_dropsOldest() throws {
        let inbox = makeInbox()
        for index in 0..<ShareInbox.maximumItems {
            try inbox.write(item("n\(index)", at: clock.addingTimeInterval(Double(index))))
        }
        try inbox.write(item("neu", at: clock.addingTimeInterval(100)))
        let titles = inbox.pending().map(\.title)
        #expect(titles.count == ShareInbox.maximumItems)
        #expect(!titles.contains("n0"))
        #expect(titles.last == "neu")
    }

    @Test func remove_deletesFiles() throws {
        let inbox = makeInbox()
        let stored = try inbox.write(item("mit Datei", target: .note),
                                     copying: [ShareInboxSource(url: try makeSourceFile("b.pdf"), name: "b.pdf", typeIdentifier: "com.adobe.pdf")])
        let file = try #require(stored.files.first)
        #expect(inbox.fileURL(for: file, in: stored) != nil)
        inbox.remove(stored.id)
        #expect(inbox.pending().isEmpty)
        #expect(inbox.fileURL(for: file, in: stored) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inboxDirectory.path).isEmpty)
    }

    @Test func markOffered_increments() throws {
        let inbox = makeInbox()
        let stored = try inbox.write(item("x"))
        inbox.markOffered(stored.id)
        inbox.markOffered(stored.id)
        #expect(inbox.pending().first?.offeredCount == 2)
        inbox.markOffered(UUID())  // unknown ID: nothing happens
        #expect(inbox.pending().count == 1)
    }

    @Test func resetOffers_startsAgain() throws {
        let inbox = makeInbox()
        let stored = try inbox.write(item("x"))
        inbox.markOffered(stored.id)
        inbox.markOffered(stored.id)
        inbox.resetOffers(stored.id)
        #expect(inbox.pending().first?.offeredCount == 0)
    }

    @Test func filesAreCopiedNotMoved() throws {
        let inbox = makeInbox()
        let source = try makeSourceFile("c.png", bytes: 42)
        let stored = try inbox.write(item("Bild", target: .note), copying: [ShareInboxSource(url: source, name: "c.png", typeIdentifier: "public.png")])
        #expect(FileManager.default.fileExists(atPath: source.path))
        let file = try #require(stored.files.first)
        #expect(file.byteCount == 42)
        #expect(file.typeIdentifier == "public.png")
        let copy = try #require(inbox.fileURL(for: file, in: stored))
        #expect(try Data(contentsOf: copy).count == 42)
    }

    @Test func fileNames_areSafeAndUnique() throws {
        let inbox = makeInbox()
        let source = try makeSourceFile("d.txt")
        let stored = try inbox.write(item("Namen"), copying: [
            ShareInboxSource(url: source, name: "../../evil.txt", typeIdentifier: "public.plain-text"),
            ShareInboxSource(url: source, name: "evil.txt", typeIdentifier: "public.plain-text"),
            ShareInboxSource(url: source, name: ".hidden", typeIdentifier: "public.plain-text"),
        ])
        #expect(stored.files.map(\.name) == ["evil.txt", "evil 2.txt", "hidden"])
        #expect(stored.files.allSatisfy { $0.relativePath.hasPrefix(stored.id.uuidString + "/") })
    }

    @Test func unreadableSource_writesNothing() throws {
        let inbox = makeInbox()
        let missing = root.appending(path: "missing.bin")
        #expect(throws: ShareInbox.Failure.unreadableSource) {
            try inbox.write(self.item("kaputt"), copying: [ShareInboxSource(url: missing, name: "missing.bin", typeIdentifier: "public.data")])
        }
        #expect(inbox.pending().isEmpty)
    }

    @Test func inboxFolder_isExcludedFromBackup() throws {
        let inbox = makeInbox()
        try inbox.write(item("x"))
        let values = try inboxDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
