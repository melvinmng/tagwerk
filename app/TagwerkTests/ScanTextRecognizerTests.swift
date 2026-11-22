import Foundation
import SwiftData
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

/// Text recognition of scans: the recogniser itself, what is done with its result and where the result may go.
@MainActor
struct ScanTextRecognizerTests {
    let container: ModelContainer
    let directory: URL
    let attachments: NoteAttachmentStore
    let notes: NoteStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appending(path: "recognition-" + UUID().uuidString, directoryHint: .isDirectory)
        attachments = NoteAttachmentStore(context: container.mainContext, directory: directory)
        notes = NoteStore(context: container.mainContext, attachments: attachments)
    }

    /// Records how often it was asked and answers with a fixed result.
    final class FakeRecognizer: ScanTextRecognizing, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let result: Result<String, any Error>
        init(_ result: Result<String, any Error>) { self.result = result }
        var callCount: Int { lock.withLock { calls } }
        func text(inPDF data: Data) async throws -> String {
            lock.withLock { calls += 1 }
            return try result.get()
        }
    }

    struct Failure: Error {}

    private func addScan(to noteID: UUID, pages: Int = 1) throws -> NoteAttachmentRecord {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let page = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        let pdf = ScanPDFBuilder.pdf(pages: Array(repeating: page, count: pages))
        return try attachments.addData(pdf, fileName: "Scan.pdf", type: .pdf, role: .scan, to: noteID, pageCount: pages)
    }

    // MARK: The recogniser

    @Test func recognizer_findsGermanWord() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1400, height: 300)
        let page = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("Kündigungsfrist drei Monate" as NSString).draw(at: CGPoint(x: 40, y: 90), withAttributes: [.font: UIFont.systemFont(ofSize: 96), .foregroundColor: UIColor.black])
        }
        let pdf = ScanPDFBuilder.pdf(pages: [page])
        let text: String
        do {
            text = try await VisionScanTextRecognizer().text(inPDF: pdf)
        } catch {
            // Vision may be missing in the simulator of a test run; the device check (Z1) covers it then.
            withKnownIssue("Vision text recognition is not available in this simulator (checked on the device): \(error)") { throw error }
            return
        }
        guard !text.isEmpty else {
            withKnownIssue("Vision text recognition returned nothing in this simulator (checked on the device)") { Issue.record("empty result") }
            return
        }
        // Case and diacritics are tolerated: recognition is not exact.
        #expect(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains("kundigungsfrist"))
    }

    @Test func recognizer_rejectsDataThatIsNoPDF() async {
        await #expect(throws: ScanTextRecognitionError.self) { try await VisionScanTextRecognizer().text(inPDF: Data("kein PDF".utf8)) }
    }

    // MARK: What is done with the result

    @Test func recognition_storesTextOnRecord() async throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try addScan(to: note.id)
        #expect(scan.recognizedText == nil)
        await ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: FakeRecognizer(.success("Kündigungsfrist drei Monate"))).value
        #expect(attachments.record(id: scan.id)?.recognizedText == "Kündigungsfrist drei Monate")
    }

    @Test func recognition_failureLeavesEmptyTextForANewTry() async throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try addScan(to: note.id)
        await ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: FakeRecognizer(.failure(Failure()))).value
        #expect(attachments.record(id: scan.id)?.recognizedText == "")
        // A new try after "Text erkennen": pending again, then recognised.
        attachments.setRecognizedTextPending(for: scan.id)
        #expect(attachments.record(id: scan.id)?.recognizedText == nil)
        await ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: FakeRecognizer(.success("Jetzt da"))).value
        #expect(attachments.record(id: scan.id)?.recognizedText == "Jetzt da")
    }

    @Test func recognition_runsOncePerScanAtATime() async throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try addScan(to: note.id)
        let recognizer = FakeRecognizer(.success("Text"))
        let first = ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: recognizer)
        let second = ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: recognizer)
        await first.value
        await second.value
        #expect(recognizer.callCount == 1)
    }

    @Test func recognition_ofARemovedScan_changesNothing() async throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try addScan(to: note.id)
        let task = ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: FakeRecognizer(.success("Text")))
        attachments.delete(ids: [scan.id])
        await task.value
        #expect(attachments.records().isEmpty)
    }

    @Test func recognition_reportsWhenFinished() async throws {
        let note = try #require(notes.create(text: "Scan"))
        let scan = try addScan(to: note.id)
        var finished = 0
        await ScanTextRecognition.start(for: scan.id, store: attachments, recognizer: FakeRecognizer(.success("Text"))) { finished += 1 }.value
        #expect(finished == 1)
    }

    @Test func scansAwaitingRecognition_areThoseWithoutAnyResult() async throws {
        let note = try #require(notes.create(text: "Scan"))
        let pending = try addScan(to: note.id)
        let done = try addScan(to: note.id)
        let empty = try addScan(to: note.id)
        attachments.setRecognizedText("Text", for: done.id)
        attachments.setRecognizedText("", for: empty.id)
        #expect(attachments.scansAwaitingRecognition(of: note.id) == [pending.id])
    }

    @Test func detail_namesTheStateOfRecognition() throws {
        #expect(NoteAttachmentStore.scanDetail(pages: 8, size: "3,1 MB", recognizedText: nil) == "8 Seiten · 3,1 MB · PDF · Text wird erkannt …")
        #expect(NoteAttachmentStore.scanDetail(pages: 8, size: "3,1 MB", recognizedText: "Wort") == "8 Seiten · 3,1 MB · PDF · Text erkannt")
        #expect(NoteAttachmentStore.scanDetail(pages: 1, size: "3,1 MB", recognizedText: "") == "1 Seite · 3,1 MB · PDF")
    }

    // MARK: Where the text may go

    @Test func scanText_joinsRecognizedTextsOfReferencedScans() throws {
        let note = try #require(notes.create(text: "Scan"))
        let first = try addScan(to: note.id)
        let second = try addScan(to: note.id)
        let unreferenced = try addScan(to: note.id)
        let plain = try attachments.addData(Data([1]), fileName: "a.pdf", type: .pdf, role: .plain, to: note.id)
        attachments.setRecognizedText("Eins", for: first.id)
        attachments.setRecognizedText("Zwei", for: second.id)
        attachments.setRecognizedText("Nie", for: unreferenced.id)
        attachments.setRecognizedText("Kein Scan", for: plain.id)
        let text = [first.id, second.id, plain.id].map { MarkdownText.reference(for: $0, name: "x", isImage: false) }.joined(separator: "\n")
        #expect(NoteAttachmentStore.scanText(text: text, index: attachments.index()) == "Eins\n\nZwei")
        #expect(NoteAttachmentStore.scanText(text: "ohne Verweis", index: attachments.index()) == "")
    }

    @Test func appSearch_carriesScanText_assistantNever() throws {
        let note = try #require(notes.create(text: "Mietvertrag\nUnterschrieben"))
        let scan = try addScan(to: note.id)
        attachments.setRecognizedText("Die Kündigungsfrist beträgt drei Monate", for: scan.id)
        note.text += "\n" + MarkdownText.reference(for: scan.id, name: "Scan", isImage: false)
        notes.save()
        let texts = AppEnvironment.scanTexts(of: notes.notes(), attachments: attachments)
        #expect(texts[note.id]?.contains("Kündigungsfrist") == true)
        let appItems = AppEnvironment.appSearchNotes(live: notes.notes(), folderNames: [:], gratitudeDays: [:], calendar: testCalendar(), scanTexts: texts)
        #expect(appItems.first { $0.id == note.id }?.scanText.contains("Kündigungsfrist") == true)
        // The note text itself does not hold the recognised text.
        #expect(appItems.first { $0.id == note.id }?.text.contains("Kündigungsfrist") == false)
        // The assistant's source never sets it, not even for a note it may read.
        let assistantItems = AppEnvironment.assistantSearchNotes(store: notes)
        #expect(assistantItems.contains { $0.id == note.id })
        #expect(assistantItems.allSatisfy { $0.scanText.isEmpty && !$0.text.contains("Kündigungsfrist") })
    }

    @Test func noteWithoutScan_hasNoScanText() throws {
        let note = try #require(notes.create(text: "Nur Text"))
        #expect(AppEnvironment.scanTexts(of: [note], attachments: attachments).isEmpty)
        #expect(AppEnvironment.scanTexts(of: [note], attachments: nil).isEmpty)
    }
}
