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

    // MARK: Generated data, roles and companions

    private func makePDF(pageColors: [UIColor], size: CGSize = CGSize(width: 200, height: 300)) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            for color in pageColors {
                context.beginPage()
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
    }

    private func makePNG(color: UIColor, size: CGSize = CGSize(width: 40, height: 30)) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// The colour of the middle pixel of a picture.
    private func centerPixel(of image: UIImage) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = image.cgImage,
              let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return pixel }
        context.draw(cgImage, in: CGRect(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2,
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return pixel
    }

    private func addDrawing(to note: NoteRecord) throws -> (picture: NoteAttachmentRecord, strokes: NoteAttachmentRecord) {
        let picture = try attachments.addData(makePNG(color: .white), fileName: "Zeichnung.png", type: .png, role: .drawing, to: note.id)
        let strokes = try attachments.addData(Data([1, 2, 3]), fileName: "Zeichnung.strokes", type: .data, role: .strokes, to: note.id,
                                              companionOf: picture.id)
        return (picture, strokes)
    }

    @Test func addData_storesRoleAndPageCount() throws {
        let note = try #require(notes.create(text: "Scan"))
        let pdf = makePDF(pageColors: [.red, .blue])
        let record = try attachments.addData(pdf, fileName: "Scan 20.11.2026.pdf", type: .pdf, role: .scan, to: note.id, pageCount: 2)
        #expect(record.roleRaw == "scan" && record.pageCount == 2 && record.companionOfID == nil && record.recognizedText == nil)
        #expect(record.fileName == "Scan 20.11.2026.pdf" && record.typeIdentifier == "com.adobe.pdf" && record.byteCount == pdf.count)
        #expect(attachments.data(for: record.id) == pdf)
        #expect(filesOnDisk() == ["\(record.id.uuidString).pdf"])
        // A picture or file that was added the usual way has no role.
        let plain = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: note.id)
        #expect(plain.roleRaw == "" && plain.pageCount == 0 && plain.companionOfID == nil)
    }

    @Test func addData_tooLargeThrows() throws {
        let note = try #require(notes.create(text: "Scan"))
        #expect(throws: NoteAttachmentStore.Failure.tooLarge) {
            try attachments.addData(Data(count: NoteAttachmentStore.maximumFileBytes + 1), fileName: "gross.pdf", type: .pdf, role: .scan, to: note.id)
        }
        #expect(attachments.records().isEmpty && filesOnDisk().isEmpty)
    }

    @Test func replaceData_keepsID() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let record = try attachments.addData(makePNG(color: .red), fileName: "Zeichnung.png", type: .png, role: .drawing, to: note.id)
        let before = try #require(attachments.thumbnail(for: record.id))
        #expect(centerPixel(of: before)[0] > 200 && centerPixel(of: before)[2] < 60)
        let bigger = makePNG(color: .blue, size: CGSize(width: 80, height: 60))
        try attachments.replaceData(bigger, for: record.id)
        #expect(record.id == attachments.records().first?.id && attachments.records().count == 1)
        #expect(attachments.data(for: record.id) == bigger)
        #expect(attachments.record(id: record.id)?.byteCount == bigger.count)
        #expect(filesOnDisk() == ["\(record.id.uuidString).png"])
        // The cached small picture is not the old one.
        let after = try #require(attachments.thumbnail(for: record.id))
        #expect(centerPixel(of: after)[2] > 200 && centerPixel(of: after)[0] < 60)
        #expect(throws: NoteAttachmentStore.Failure.unreadable) { try attachments.replaceData(bigger, for: UUID()) }
        #expect(throws: NoteAttachmentStore.Failure.tooLarge) {
            try attachments.replaceData(Data(count: NoteAttachmentStore.maximumFileBytes + 1), for: record.id)
        }
    }

    @Test func companion_isFoundByParentAndRole() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        #expect(attachments.companion(of: drawing.picture.id, role: .strokes)?.id == drawing.strokes.id)
        #expect(attachments.companion(of: drawing.picture.id, role: .drawing) == nil)
        #expect(attachments.companion(of: UUID(), role: .strokes) == nil)
    }

    @Test func removeUnreferenced_takesCompanionWithParent() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        attachments.removeUnreferenced(noteID: note.id, text: "Kein Verweis mehr")
        #expect(attachments.records().isEmpty && filesOnDisk().isEmpty)
        #expect(attachments.record(id: drawing.strokes.id) == nil)
    }

    @Test func removeUnreferenced_keepsCompanionWhileParentReferenced() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        let text = MarkdownText.reference(for: drawing.picture.id, name: "Zeichnung", isImage: true)
        attachments.removeUnreferenced(noteID: note.id, text: text)
        #expect(attachments.record(id: drawing.picture.id) != nil && attachments.record(id: drawing.strokes.id) != nil)
        #expect(filesOnDisk().count == 2)
    }

    @Test func removeUnreferenced_dropsCompanionWhoseParentIsGone() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let stray = try attachments.addData(Data([9]), fileName: "Rest.strokes", type: .data, role: .strokes, to: note.id, companionOf: UUID())
        attachments.removeUnreferenced(noteID: note.id, text: "Text")
        #expect(attachments.record(id: stray.id) == nil && filesOnDisk().isEmpty)
    }

    @Test func delete_takesCompanionsAlong() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        let other = try attachments.addFile(at: makeFile(named: "b.pdf", bytes: 10), to: note.id)
        attachments.delete(ids: [drawing.picture.id])
        #expect(attachments.records().map(\.id) == [other.id])
        #expect(filesOnDisk() == ["\(other.id.uuidString).pdf"])
    }

    @Test func purgeOrphans_keepsCompanionFile() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        attachments.purgeOrphans(existingNoteIDs: [note.id])
        #expect(attachments.url(for: drawing.picture.id) != nil && attachments.url(for: drawing.strokes.id) != nil)
        // With the note gone, both go.
        attachments.purgeOrphans(existingNoteIDs: [UUID()])
        #expect(attachments.records().isEmpty && filesOnDisk().isEmpty)
    }

    @Test func deleteNote_deletesDrawingWithItsCompanion() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        _ = try addDrawing(to: note)
        notes.delete(note.id)
        #expect(attachments.records().isEmpty && filesOnDisk().isEmpty)
    }

    @Test func cardInfo_ignoresCompanions() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        let text = MarkdownText.reference(for: drawing.picture.id, name: "Zeichnung", isImage: true) + "\n"
            + MarkdownText.reference(for: drawing.strokes.id, name: "Striche", isImage: false)
        let info = NoteAttachmentStore.cardInfo(text: text, index: attachments.index())
        #expect(info.firstImageID == drawing.picture.id && info.fileCount == 0)
    }

    @Test func cardInfo_scanCountsAsImage() throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try attachments.addData(makePDF(pageColors: [.red]), fileName: "Scan.pdf", type: .pdf, role: .scan, to: note.id, pageCount: 1)
        let plain = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: note.id)
        let text = [scan.id, plain.id].map { MarkdownText.reference(for: $0, name: "x", isImage: false) }.joined(separator: "\n")
        let info = NoteAttachmentStore.cardInfo(text: text, index: attachments.index())
        #expect(info.firstImageID == scan.id && info.fileCount == 1)
    }

    @Test func thumbnail_ofPDFIsFirstPage() throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try attachments.addData(makePDF(pageColors: [.red, .blue]), fileName: "Scan.pdf", type: .pdf, role: .scan, to: note.id, pageCount: 2)
        let thumbnail = try #require(attachments.thumbnail(for: scan.id))
        let pixel = centerPixel(of: thumbnail)
        #expect(pixel[0] > 200 && pixel[2] < 60)
        #expect(max(thumbnail.size.width, thumbnail.size.height) * thumbnail.scale <= 96 * 3)
    }

    @Test func exportURLs_skipCompanions() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        let file = try attachments.addFile(at: makeFile(named: "a.pdf", bytes: 10), to: note.id)
        let text = [drawing.picture.id, drawing.strokes.id, file.id].map { MarkdownText.reference(for: $0, name: "x", isImage: false) }.joined(separator: "\n")
        let urls = attachments.shareableURLs(of: note.id, text: text)
        #expect(urls.map(\.lastPathComponent).sorted() == ["Zeichnung.png", "a.pdf"])
    }

    @Test func displays_skipCompanions() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let drawing = try addDrawing(to: note)
        #expect(Set(attachments.displays(of: note.id).keys) == [drawing.picture.id])
    }

    @Test func duplicate_copiesCompanionAndFields() throws {
        let note = try #require(notes.create(text: "Zeichnung"))
        let scan = try attachments.addData(makePDF(pageColors: [.red, .blue]), fileName: "Scan.pdf", type: .pdf, role: .scan, to: note.id, pageCount: 2)
        attachments.setRecognizedText("Kündigungsfrist", for: scan.id)
        let drawing = try addDrawing(to: note)
        let target = try #require(notes.create(text: "Kopie"))
        let mapping = attachments.duplicate(ids: [scan.id, drawing.picture.id], to: target.id)
        let copiedScan = try #require(mapping[scan.id].flatMap(attachments.record(id:)))
        #expect(copiedScan.roleRaw == "scan" && copiedScan.pageCount == 2 && copiedScan.recognizedText == "Kündigungsfrist" && copiedScan.noteID == target.id)
        let copiedPicture = try #require(mapping[drawing.picture.id].flatMap(attachments.record(id:)))
        let copiedStrokes = try #require(attachments.companion(of: copiedPicture.id, role: .strokes))
        #expect(copiedStrokes.id != drawing.strokes.id && copiedStrokes.noteID == target.id)
        #expect(attachments.data(for: copiedStrokes.id) == Data([1, 2, 3]))
        // The original keeps its own companion.
        #expect(attachments.companion(of: drawing.picture.id, role: .strokes)?.id == drawing.strokes.id)
    }

    @Test func rename_keepsExtensionAndFile() throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try attachments.addData(makePDF(pageColors: [.red]), fileName: "Scan 20.11.2026.pdf", type: .pdf, role: .scan, to: note.id, pageCount: 1)
        attachments.rename(scan.id, to: "Mietvertrag")
        #expect(attachments.record(id: scan.id)?.fileName == "Mietvertrag.pdf")
        #expect(attachments.url(for: scan.id) != nil && filesOnDisk() == ["\(scan.id.uuidString).pdf"])
        attachments.rename(scan.id, to: "Anlage 2.PDF")
        #expect(attachments.record(id: scan.id)?.fileName == "Anlage 2.pdf")
        attachments.rename(scan.id, to: "  ")
        attachments.rename(scan.id, to: "a/b")
        #expect(attachments.record(id: scan.id)?.fileName == "a-b.pdf")
    }

    @Test func setRecognizedText_isStoredOnTheRecord() throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try attachments.addData(makePDF(pageColors: [.red]), fileName: "Scan.pdf", type: .pdf, role: .scan, to: note.id, pageCount: 1)
        #expect(scan.recognizedText == nil)
        attachments.setRecognizedText("Hallo Welt", for: scan.id)
        #expect(attachments.record(id: scan.id)?.recognizedText == "Hallo Welt")
        attachments.setRecognizedText("", for: scan.id)
        #expect(attachments.record(id: scan.id)?.recognizedText == "")
    }
}
