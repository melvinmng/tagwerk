import Foundation
import SwiftData
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

/// Pictures and files of the notes. All files are invented and live in a temporary folder.
@MainActor
struct NoteAttachmentStoreTests {
    final class Clock { var now = testNow() }
    let container: ModelContainer
    let clock = Clock()
    let directory: URL
    let attachments: NoteAttachmentStore
    let notes: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appending(path: "attachments-" + UUID().uuidString, directoryHint: .isDirectory)
        let clock = self.clock
        attachments = NoteAttachmentStore(context: container.mainContext, directory: directory, now: { clock.now })
        notes = NoteStore(context: container.mainContext, now: { clock.now }, attachments: attachments)
    }

    private func makeImage(width: CGFloat = 4000, height: CGFloat = 3000) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makeFile(named name: String, bytes: Int) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "source-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func filesOnDisk() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test func addImage_storesDownscaledJPEG() throws {
        let note = try #require(notes.create(text: "Foto"))
        let record = try attachments.addImage(makeImage(), to: note.id)
        #expect(record.noteID == note.id && record.fileName == "Foto.jpg" && record.typeIdentifier == "public.jpeg")
        let data = try #require(attachments.data(for: record.id))
        #expect(record.byteCount == data.count)
        let stored = try #require(UIImage(data: data))
        let longestEdge = max(stored.size.width * stored.scale, stored.size.height * stored.scale)
        #expect(longestEdge == NoteAttachmentStore.maximumImageEdge)
        #expect(filesOnDisk() == ["\(record.id.uuidString).jpg"])
        #expect(attachments.attachments(of: note.id).map(\.id) == [record.id])
    }

    @Test func displays_namesSizeAndKind() throws {
        let note = try #require(notes.create(text: "Anhänge"))
        let image = try attachments.addImage(makeImage(width: 40, height: 30), to: note.id)
        let file = try attachments.addFile(at: makeFile(named: "Rechnung.pdf", bytes: 2048), to: note.id)
        let other = try #require(notes.create(text: "Andere"))
        let foreign = try attachments.addFile(at: makeFile(named: "Fremd.pdf", bytes: 10), to: other.id)
        let displays = attachments.displays(of: note.id)
        #expect(Set(displays.keys) == [image.id, file.id])
        #expect(displays[foreign.id] == nil)
        #expect(displays[file.id]?.name == "Rechnung.pdf" && displays[file.id]?.kind == .file)
        #expect(displays[file.id]?.detail == ByteCountFormatter.string(fromByteCount: 2048, countStyle: .file))
        #expect(displays[image.id]?.kind == .image && displays[image.id]?.name == "Foto.jpg")
    }

    @Test func addImage_fromData_andFromNonImage() throws {
        let note = try #require(notes.create(text: "Foto"))
        let png = try #require(makeImage(width: 100, height: 50).pngData())
        let record = try attachments.addImage(data: png, to: note.id)
        #expect(record.fileName == "Foto.jpg")
        #expect(throws: NoteAttachmentStore.Failure.notAnImage) { try attachments.addImage(data: Data("kein Bild".utf8), to: note.id) }
    }

    @Test func addFile_copiesAndRecordsSize() throws {
        let note = try #require(notes.create(text: "Datei"))
        let source = try makeFile(named: "Rechnung.PDF", bytes: 2048)
        let record = try attachments.addFile(at: source, to: note.id)
        #expect(record.fileName == "Rechnung.PDF" && record.byteCount == 2048 && record.typeIdentifier == "com.adobe.pdf")
        let url = try #require(attachments.url(for: record.id))
        #expect(url.lastPathComponent == "\(record.id.uuidString).pdf")
        #expect(try Data(contentsOf: url).count == 2048)
        // The original stays where it was.
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(attachments.summary.count == 1 && attachments.summary.bytes == 2048)
    }

    @Test func addFile_over25MB_throwsTooLarge() throws {
        let note = try #require(notes.create(text: "Datei"))
        let source = try makeFile(named: "gross.bin", bytes: NoteAttachmentStore.maximumFileBytes + 1)
        #expect(throws: NoteAttachmentStore.Failure.tooLarge) { try attachments.addFile(at: source, to: note.id) }
        #expect(attachments.records().isEmpty && filesOnDisk().isEmpty)
        // Exactly the limit is fine.
        let limit = try makeFile(named: "genau.bin", bytes: NoteAttachmentStore.maximumFileBytes)
        #expect(try attachments.addFile(at: limit, to: note.id).byteCount == NoteAttachmentStore.maximumFileBytes)
    }

    @Test func addFile_missingFile_throwsUnreadable() throws {
        let note = try #require(notes.create(text: "Datei"))
        #expect(throws: NoteAttachmentStore.Failure.unreadable) {
            try attachments.addFile(at: directory.appending(path: "gibt-es-nicht.pdf"), to: note.id)
        }
    }

    @Test func removeUnreferenced_deletesOnlyDroppedOnes() throws {
        let note = try #require(notes.create(text: "Anhänge"))
        let other = try #require(notes.create(text: "Andere Notiz"))
        let kept = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: note.id)
        let dropped = try attachments.addFile(at: makeFile(named: "b.pdf", bytes: 10), to: note.id)
        let foreign = try attachments.addFile(at: makeFile(named: "c.pdf", bytes: 10), to: other.id)
        let text = "Siehe " + MarkdownText.reference(for: kept.id, name: "a.pdf", isImage: false)
        attachments.removeUnreferenced(noteID: note.id, text: text)
        #expect(attachments.url(for: kept.id) != nil)
        #expect(attachments.url(for: dropped.id) == nil && attachments.record(id: dropped.id) == nil)
        // Another note's attachment is never touched.
        #expect(attachments.url(for: foreign.id) != nil)
        #expect(filesOnDisk().count == 2)
    }

    @Test func trash_keepsAttachments() throws {
        let note = try #require(notes.create(text: "Anhang"))
        let record = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: note.id)
        notes.trash(note.id)
        #expect(attachments.url(for: record.id) != nil)
        notes.restore(note.id)
        #expect(attachments.url(for: record.id) != nil)
        // Deleting a folder only moves its notes to the trash.
        let folder = try notes.createFolder(name: "Ordner")
        notes.move(noteIDs: [note.id], to: folder.id)
        try notes.deleteFolder(folder.id)
        #expect(attachments.url(for: record.id) != nil && note.deletedAt != nil)
    }

    @Test func emptyTrash_deletesAttachments() throws {
        let trashed = try #require(notes.create(text: "Weg"))
        let live = try #require(notes.create(text: "Bleibt"))
        let goneFile = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: trashed.id)
        let keptFile = try attachments.addFile(at: makeFile(named: "b.pdf", bytes: 10), to: live.id)
        notes.trash(trashed.id)
        notes.emptyTrash()
        #expect(attachments.url(for: goneFile.id) == nil && attachments.url(for: keptFile.id) != nil)
    }

    @Test func purgeExpired_deletesAttachments() throws {
        let note = try #require(notes.create(text: "Alt"))
        let record = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: note.id)
        notes.trash(note.id)
        #expect(notes.purgeExpired(now: clock.now.addingTimeInterval(10 * 86_400)) == 0)
        #expect(attachments.url(for: record.id) != nil)
        #expect(notes.purgeExpired(now: clock.now.addingTimeInterval(31 * 86_400)) == 1)
        #expect(attachments.url(for: record.id) == nil && filesOnDisk().isEmpty)
    }

    @Test func delete_andDeleteIfEmpty_deleteAttachments() throws {
        let first = try #require(notes.create(text: "Eins"))
        let second = try #require(notes.create(text: "Zwei"))
        let a = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: first.id)
        let b = try attachments.addFile(at: makeFile(named: "b.pdf", bytes: 10), to: second.id)
        notes.delete(first.id)
        #expect(attachments.url(for: a.id) == nil)
        notes.updateText(second.id, text: "  ")
        notes.deleteIfEmpty(second.id)
        #expect(attachments.url(for: b.id) == nil && filesOnDisk().isEmpty)
    }

    @Test func purgeOrphans_removesFilesWithoutNote() throws {
        let live = try #require(notes.create(text: "Lebt"))
        let kept = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: live.id)
        let lost = try attachments.addFile(at: makeFile(named: "b.pdf", bytes: 10), to: UUID())
        // A file in the folder that no record knows.
        try Data("x".utf8).write(to: directory.appending(path: "\(UUID().uuidString).bin"))
        attachments.purgeOrphans(existingNoteIDs: [live.id])
        #expect(attachments.url(for: kept.id) != nil && attachments.record(id: lost.id) == nil)
        #expect(filesOnDisk() == ["\(kept.id.uuidString).pdf"])
    }

    @Test func purgeOrphans_withoutAnyNote_removesNothing() throws {
        let record = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: UUID())
        attachments.purgeOrphans(existingNoteIDs: [])
        #expect(attachments.url(for: record.id) != nil)
    }

    @Test func schema_containsNoteAttachmentRecord() {
        #expect(ModelContainerFactory.schema.entities.contains { $0.name == "NoteAttachmentRecord" })
    }

    // MARK: Duplicating

    @Test func duplicateAttachments_newRecordsNewFiles() throws {
        let source = try #require(notes.create(text: "Original"))
        let target = try #require(notes.create(text: "Kopie"))
        let file = try attachments.addFile(at: makeFile(named: "Rechnung.pdf", bytes: 64), to: source.id)
        let image = try attachments.addImage(makeImage(width: 40, height: 30), to: source.id)
        clock.now = clock.now.addingTimeInterval(3_600)
        let mapping = attachments.duplicate(ids: [file.id, image.id], to: target.id)
        #expect(Set(mapping.keys) == [file.id, image.id])
        #expect(Set(mapping.values).isDisjoint(with: [file.id, image.id]))
        let copiedFileID = try #require(mapping[file.id])
        let copiedFile = try #require(attachments.record(id: copiedFileID))
        #expect(copiedFile.noteID == target.id && copiedFile.fileName == "Rechnung.pdf" && copiedFile.typeIdentifier == "com.adobe.pdf")
        #expect(copiedFile.byteCount == 64 && copiedFile.createdAt == file.createdAt)
        #expect(attachments.data(for: copiedFile.id) == attachments.data(for: file.id))
        let copiedImageID = try #require(mapping[image.id])
        let copiedImage = try #require(attachments.record(id: copiedImageID))
        #expect(copiedImage.fileName == "Foto.jpg" && copiedImage.noteID == target.id)
        #expect(attachments.attachments(of: target.id).count == 2 && filesOnDisk().count == 4)
    }

    @Test func duplicateAttachments_missingFileIsSkipped() throws {
        let source = try #require(notes.create(text: "Original"))
        let target = try #require(notes.create(text: "Kopie"))
        let kept = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 8), to: source.id)
        let lost = try attachments.addFile(at: makeFile(named: "b.pdf", bytes: 8), to: source.id)
        let lostURL = try #require(attachments.url(for: lost.id))
        try FileManager.default.removeItem(at: lostURL)
        let mapping = attachments.duplicate(ids: [kept.id, lost.id, UUID()], to: target.id)
        #expect(Set(mapping.keys) == [kept.id])
        #expect(attachments.attachments(of: target.id).count == 1)
    }

    @Test func duplicate_createsNoteInSameFolderWithRewrittenReferences() throws {
        let folder = try notes.createFolder(name: "Rezepte")
        let original = try #require(notes.create(text: "Curry", folderID: folder.id))
        let image = try attachments.addImage(makeImage(width: 40, height: 30), to: original.id)
        let file = try attachments.addFile(at: makeFile(named: "Quelle.pdf", bytes: 16), to: original.id)
        let text = "# Curry\n\n" + MarkdownText.reference(for: image.id, name: "Foto", isImage: true)
            + "\n" + MarkdownText.reference(for: file.id, name: "Quelle.pdf", isImage: false) + "\n"
        notes.updateText(original.id, text: text)
        original.isPinned = true
        let copy = try #require(notes.duplicate(original.id, text: "# Rotes Curry\n\n" + text.components(separatedBy: "\n\n")[1]))
        #expect(copy.id != original.id && copy.folderID == folder.id && copy.kind == .free && !copy.isPinned)
        let ids = MarkdownText.attachmentIDs(in: copy.text)
        #expect(ids.count == 2 && ids.isDisjoint(with: [image.id, file.id]))
        #expect(Set(attachments.attachments(of: copy.id).map(\.id)) == ids)
        #expect(copy.text.hasPrefix("# Rotes Curry"))
        // The original is untouched.
        #expect(original.text == text)
    }

    @Test func duplicate_copySurvivesDeletingTheOriginal() throws {
        let original = try #require(notes.create(text: "Curry"))
        let image = try attachments.addImage(makeImage(width: 40, height: 30), to: original.id)
        notes.updateText(original.id, text: "# Curry\n" + MarkdownText.reference(for: image.id, name: "Foto", isImage: true))
        let copy = try #require(notes.duplicate(original.id, text: original.text))
        notes.trash(original.id)
        notes.emptyTrash()
        #expect(attachments.url(for: image.id) == nil)
        let copiedID = try #require(MarkdownText.attachmentReferences(in: copy.text).first)
        #expect(attachments.url(for: copiedID) != nil)
        // Closing the copy's editor must not remove its pictures either.
        attachments.removeUnreferenced(noteID: copy.id, text: copy.text)
        #expect(attachments.url(for: copiedID) != nil)
    }

    @Test func duplicate_originalKeepsItsAttachments() throws {
        let original = try #require(notes.create(text: "Curry"))
        let image = try attachments.addImage(makeImage(width: 40, height: 30), to: original.id)
        notes.updateText(original.id, text: "# Curry\n" + MarkdownText.reference(for: image.id, name: "Foto", isImage: true))
        _ = try #require(notes.duplicate(original.id, text: original.text))
        #expect(attachments.url(for: image.id) != nil)
        #expect(attachments.attachments(of: original.id).map(\.id) == [image.id])
        #expect(MarkdownText.attachmentIDs(in: original.text) == [image.id])
    }
}
