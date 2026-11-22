import Foundation
import PDFKit
import UIKit
import Vision

/// Recognises the text of a scanned document. The result belongs to the attachment (`NoteAttachmentRecord.recognizedText`):
/// the search finds the scan by it and the person can paste it into the note, but it is never part of the note text.
protocol ScanTextRecognizing: Sendable {
    /// Recognises the text of all pages on the device (German and English), page by page, joined by blank lines.
    func text(inPDF data: Data) async throws -> String
}

enum ScanTextRecognitionError: Error {
    case unreadableDocument
}

/// Vision at the accurate level, German and English, on the device and without any network access.
struct VisionScanTextRecognizer: ScanTextRecognizing {
    /// Pages are rendered with this longer side before they go to Vision.
    static let pageEdge: CGFloat = 2048
    static let languages = ["de-DE", "en-US"]

    func text(inPDF data: Data) async throws -> String {
        guard let document = PDFDocument(data: data) else { throw ScanTextRecognitionError.unreadableDocument }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let image = NoteAttachmentStore.render(page, edge: Self.pageEdge)?.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = Self.languages
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            if !lines.isEmpty { pages.append(lines.joined(separator: "\n")) }
        }
        return pages.joined(separator: "\n\n")
    }
}

/// Runs recognition for a scan in the background and stores the result on its record.
@MainActor
enum ScanTextRecognition {
    /// The scans whose recognition is running, so one scan is never recognised twice at the same time.
    private static var running: Set<UUID> = []

    /// Starts recognition for the scan `id` at low priority and stores the text on the record: the recognised text, or the
    /// empty text when nothing was found or recognition failed (the menu of the scan then offers a new try). Returns the task,
    /// so a test can wait for it; the editor does not.
    @discardableResult
    static func start(for id: UUID, store: NoteAttachmentStore, recognizer: any ScanTextRecognizing = VisionScanTextRecognizer(),
                      onFinished: @escaping @MainActor () -> Void = {}) -> Task<Void, Never> {
        guard !running.contains(id), let data = store.data(for: id) else { return Task {} }
        running.insert(id)
        return Task {
            let recognized = try? await Task.detached(priority: .utility) { try await recognizer.text(inPDF: data) }.value
            running.remove(id)
            // The scan may be gone by now (its reference was removed and the note closed).
            store.setRecognizedText(recognized ?? "", for: id)
            onFinished()
        }
    }
}
