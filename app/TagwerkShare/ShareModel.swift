import Foundation
import ImageIO
import Observation
import TagwerkCore
import UIKit

/// The state of the share sheet: reads the shared content, lets the user choose the target and check the title, and writes
/// the item into the inbox of the App Group. The text goes along unchanged. It makes no network call and reads neither the keychain nor the store.
@MainActor
@Observable
final class ShareModel {
    enum State: Equatable {
        case loading
        case ready
        case saving
        /// Carries the target, so the confirmation can name where the item went.
        case saved(ShareTarget)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var payload: SharePayload?
    private(set) var thumbnail: UIImage?
    var target: ShareTarget = .task
    var title = ""
    private(set) var text = ""

    private var extracted: ExtractedShare?
    private var isFinished = false
    private let extensionContext: NSExtensionContext?
    private let inboxDirectory: () -> URL?

    init(extensionContext: NSExtensionContext?, inboxDirectory: @escaping () -> URL? = ShareModel.appGroupInbox) {
        self.extensionContext = extensionContext
        self.inboxDirectory = inboxDirectory
    }

    /// `<App Group>/Library/Application Support/ShareInbox`; the identifier comes from Info.plist, never from code.
    nonisolated static func appGroupInbox() -> URL? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String,
              identifier.hasPrefix("group."), !identifier.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return ShareInbox.defaultDirectory(in: container)
    }

    /// What the share contains, for the hints of the chosen target (`ShareSheetText.hints`).
    var hasFiles: Bool { !(extracted?.files.isEmpty ?? true) }
    var hasText: Bool { !(payload?.text ?? "").isEmpty }
    var hasURL: Bool { payload?.url != nil }
    var fileNames: [String] { extracted?.files.map(\.name) ?? [] }
    var hostText: String? { payload?.url?.host(percentEncoded: false) }
    var canSave: Bool { state == .ready && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Loading

    func load() async {
        guard state == .loading else { return }
        guard inboxDirectory() != nil else {
            state = .failed(String(localized: "Tagwerk kann gerade nichts übernehmen."))
            return
        }
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        do {
            let result = try await ShareExtractor.extract(from: items)
            guard var classified = SharePayload.classify(result.parts) else { throw ShareExtractionError.nothingShared }
            classified.mail = result.mail
            if let mail = result.mail, !mail.subject.isEmpty { classified.title = mail.subject }
            extracted = result
            payload = classified
            target = classified.suggestedTarget
            title = classified.title
            text = classified.text ?? ""
            thumbnail = result.files.first.flatMap { Self.thumbnail(of: $0.url) }
            state = .ready
        } catch ShareExtractionError.tooLarge {
            state = .failed(String(localized: "Zu groß für Tagwerk (höchstens 25 MB)"))
        } catch {
            state = .failed(String(localized: "Es gab nichts zum Sichern."))
        }
    }

    // MARK: Saving

    func save() async {
        guard canSave, let payload, let extracted, let directory = inboxDirectory() else { return }
        state = .saving
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100_000))
        var mail = payload.mail
        if mail != nil, target == .mailTask { mail?.subject = cleanTitle }
        let item = ShareInboxItem(
            createdAt: Date(), target: target, title: cleanTitle, text: cleanText.isEmpty ? nil : cleanText,
            url: payload.url, pageTitle: payload.pageTitle, mail: mail)
        let sources = (target == .note || target == .recipe) ? extracted.files : []
        let inbox = ShareInbox(directory: directory)
        do {
            try inbox.write(item, copying: sources)
            try? FileManager.default.removeItem(at: extracted.directory)
            state = .saved(target)
            // Two lines of confirmation need a moment; a tap closes the sheet earlier.
            try? await Task.sleep(for: .seconds(2))
            finish()
        } catch {
            // Nothing can be saved from this state again (`canSave` needs `.ready`), so the copied files must not stay behind.
            try? FileManager.default.removeItem(at: extracted.directory)
            state = .failed(String(localized: "Tagwerk kann gerade nichts übernehmen."))
        }
    }

    /// Closes the sheet after saving; safe to call twice (tap and timer).
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        extensionContext?.completeRequest(returningItems: [])
    }

    func cancel() {
        if let directory = extracted?.directory { try? FileManager.default.removeItem(at: directory) }
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    // MARK: Thumbnail

    /// A small picture read through ImageIO, so the full image is never decoded (memory limit of the extension).
    private static func thumbnail(of url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 240]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
