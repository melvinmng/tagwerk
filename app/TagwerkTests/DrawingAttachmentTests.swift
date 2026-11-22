import Foundation
import PencilKit
import SwiftData
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

/// Drawings in notes: picture, strokes and their reference. The strokes are invented.
@MainActor
struct DrawingAttachmentTests {
    let container: ModelContainer
    let directory: URL
    let attachments: NoteAttachmentStore
    let notes: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appending(path: "drawing-" + UUID().uuidString, directoryHint: .isDirectory)
        attachments = NoteAttachmentStore(context: container.mainContext, directory: directory)
        notes = NoteStore(context: container.mainContext, attachments: attachments)
    }

    /// A drawing with one black line from (20, 30) to (120, 80).
    private func drawing(color: UIColor = .black, width: CGFloat = 6) -> PKDrawing {
        let points = [CGPoint(x: 20, y: 30), CGPoint(x: 70, y: 55), CGPoint(x: 120, y: 80)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: TimeInterval(index) * 0.01, size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: path)])
    }

    private func pixels(of data: Data) throws -> (alphaInfo: CGImageAlphaInfo, corner: [UInt8], width: Int, height: Int) {
        let image = try #require(UIImage(data: data)?.cgImage)
        var corner = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &corner, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: -CGFloat(image.height) + 1, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (image.alphaInfo, corner, image.width, image.height)
    }

    @Test func png_isOpaqueWhiteBackground() throws {
        let data = DrawingAttachment.png(of: drawing(), scale: 2)
        let result = try pixels(of: data)
        // The corner of the margin is white and fully opaque, whatever the interface style is.
        #expect(result.corner == [255, 255, 255, 255])
        #expect([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(result.alphaInfo))
        // The strokes are in it: a margin of 16 pt on each side at scale 2.
        let bounds = drawing().bounds
        #expect(result.width == Int(((bounds.width + 32) * 2).rounded()))
        #expect(result.height == Int(((bounds.height + 32) * 2).rounded()))
    }

    @Test func png_drawsBlackInkAsBlackWhileTheAppIsDark() throws {
        // PencilKit shows black ink as white in dark mode; the picture is always the light version, black on white.
        let black = drawing(color: .black, width: 12)
        var data = Data()
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent { data = DrawingAttachment.png(of: black, scale: 2) }
        let image = try #require(UIImage(data: data)?.cgImage)
        let bytes = try #require(image.dataProvider?.data as Data?)
        // Some pixels are dark, so the stroke is visible on the white paper.
        #expect(bytes.filter { $0 < 60 }.count > 100)
    }

    /// The same strokes: the number, the points and the ink colour. The bytes of two serialisations of one drawing differ.
    private func isSame(_ first: PKDrawing?, _ second: PKDrawing) -> Bool {
        guard let first, first.strokes.count == second.strokes.count else { return false }
        return zip(first.strokes, second.strokes).allSatisfy { left, right in
            left.path.map { [$0.location.x, $0.location.y, $0.size.width] } == right.path.map { [$0.location.x, $0.location.y, $0.size.width] }
                && left.ink.inkType == right.ink.inkType
        }
    }

    @Test func insert_createsPictureAndCompanion() throws {
        let note = try #require(notes.create(text: "Skizze"))
        let result = try DrawingAttachment.insert(drawing(), into: note.id, store: attachments)
        #expect(result.reference == "![Zeichnung](attachment:\(result.id.uuidString))")
        let picture = try #require(attachments.record(id: result.id))
        #expect(picture.roleRaw == "drawing" && picture.typeIdentifier == "public.png" && picture.noteID == note.id)
        let strokes = try #require(attachments.companion(of: result.id, role: .strokes))
        #expect(strokes.noteID == note.id && strokes.companionOfID == result.id)
        #expect(attachments.records().count == 2)
        #expect(attachments.displays(of: note.id)[result.id]?.kind == .drawing)
    }

    @Test func update_keepsIDAndReference() throws {
        let note = try #require(notes.create(text: "Skizze"))
        let result = try DrawingAttachment.insert(drawing(), into: note.id, store: attachments)
        let before = try #require(attachments.data(for: result.id))
        let version = attachments.displays(of: note.id)[result.id]?.version
        let edited = drawing(width: 20)
        try DrawingAttachment.update(edited, id: result.id, store: attachments)
        #expect(attachments.records().count == 2)
        #expect(attachments.record(id: result.id) != nil)
        #expect(attachments.data(for: result.id) != before)
        #expect(isSame(DrawingAttachment.strokes(of: result.id, store: attachments), edited))
        #expect(!isSame(DrawingAttachment.strokes(of: result.id, store: attachments), drawing()))
        // The page gets a new address for the picture, so it loads it again.
        #expect(attachments.displays(of: note.id)[result.id]?.version != version)
        // The text still holds the one reference.
        #expect(MarkdownText.attachmentIDs(in: result.reference) == [result.id])
    }

    @Test func update_addsMissingStrokes() throws {
        let note = try #require(notes.create(text: "Skizze"))
        let result = try DrawingAttachment.insert(drawing(), into: note.id, store: attachments)
        let companion = try #require(attachments.companion(of: result.id, role: .strokes))
        attachments.delete(ids: [companion.id])
        #expect(DrawingAttachment.strokes(of: result.id, store: attachments) == nil)
        try DrawingAttachment.update(drawing(), id: result.id, store: attachments)
        #expect(DrawingAttachment.strokes(of: result.id, store: attachments) != nil)
    }

    @Test func strokes_roundTrip() throws {
        let note = try #require(notes.create(text: "Skizze"))
        let original = drawing()
        let result = try DrawingAttachment.insert(original, into: note.id, store: attachments)
        let restored = try #require(DrawingAttachment.strokes(of: result.id, store: attachments))
        #expect(isSame(restored, original))
        #expect(restored.strokes.count == 1)
    }

    @Test func strokes_missingCompanion_isNil() throws {
        let note = try #require(notes.create(text: "Skizze"))
        // A picture of a drawing without strokes (an older backup, a damaged file).
        let picture = try attachments.addData(DrawingAttachment.png(of: drawing(), scale: 2), fileName: "Zeichnung.png", type: .png, role: .drawing, to: note.id)
        #expect(DrawingAttachment.strokes(of: picture.id, store: attachments) == nil)
        // Damaged strokes read as missing, not as a crash.
        _ = try attachments.addData(Data("kaputt".utf8), fileName: "Zeichnung.strokes", type: .data, role: .strokes, to: note.id, companionOf: picture.id)
        #expect(DrawingAttachment.strokes(of: picture.id, store: attachments) == nil)
    }

    @Test func emptyDrawing_insertsNothing() throws {
        let note = try #require(notes.create(text: "Skizze"))
        #expect(throws: DrawingAttachment.Failure.empty) { try DrawingAttachment.insert(PKDrawing(), into: note.id, store: attachments) }
        #expect(attachments.records().isEmpty)
    }

    @Test func removeUnreferenced_dropsStrokesOnlyWithThePicture() throws {
        let note = try #require(notes.create(text: "Skizze"))
        let result = try DrawingAttachment.insert(drawing(), into: note.id, store: attachments)
        attachments.removeUnreferenced(noteID: note.id, text: result.reference)
        #expect(attachments.records().count == 2)
        // The reference is deleted from the text (what "Löschen" in the menu does): both files go.
        let updated = MarkdownText.removingReference(to: result.id, in: "Text\n" + result.reference)
        #expect(updated == "Text")
        attachments.removeUnreferenced(noteID: note.id, text: updated)
        #expect(attachments.records().isEmpty)
    }

    @Test func backup_roundTripKeepsDrawingEditable() throws {
        let note = try #require(notes.create(text: "Skizze"))
        let original = drawing()
        let result = try DrawingAttachment.insert(original, into: note.id, store: attachments)
        let entities = attachments.records().compactMap { record in attachments.data(for: record.id).map { NoteAttachmentBackup(record, data: $0) } }
        let encoded = try JSONEncoder().encode(entities)
        let decoded = try JSONDecoder().decode([NoteAttachmentBackup].self, from: encoded)
        let targetContainer = try ModelContainerFactory.make(inMemory: true)
        let target = NoteAttachmentStore(context: targetContainer.mainContext,
                                         directory: FileManager.default.temporaryDirectory.appending(path: "drawing-target-" + UUID().uuidString, directoryHint: .isDirectory))
        for item in decoded {
            try target.restore(id: item.id, noteID: item.noteID, fileName: item.fileName, typeIdentifier: item.typeIdentifier, createdAt: item.createdAt,
                               data: item.data, roleRaw: item.roleRaw ?? "", companionOfID: item.companionOfID, recognizedText: item.recognizedText,
                               pageCount: item.pageCount ?? 0)
        }
        #expect(isSame(DrawingAttachment.strokes(of: result.id, store: target), original))
        withExtendedLifetime(targetContainer) {}
    }
}
