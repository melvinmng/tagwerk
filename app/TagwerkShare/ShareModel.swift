import Foundation
import ImageIO
import Observation
import TagwerkCore
import UIKit

/// The state of the share sheet: reads the shared content, lets the user check target, title and text, and writes the
/// item into the inbox of the App Group. It makes no network call and reads neither the keychain nor the store.
@MainActor
@Observable
final class ShareModel {
    enum State: Equatable {
        case loading
        case ready
        case saving
        case saved
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var payload: SharePayload?
    private(set) var thumbnail: UIImage?
    var target: ShareTarget = .task
    var title = ""
    var text = ""

    private var extracted: ExtractedShare?
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

    /// Whether the files of the share are dropped for the chosen target.
    var dropsFiles: Bool { target != .note && target != .recipe && !(extracted?.files.isEmpty ?? true) }
    var fileNames: [String] { extracted?.files.map(\.name) ?? [] }
    var hostText: String? { payload?.url?.host(percentEncoded: false) }
    /// The mail text is not edited here; the app shows it.
    var showsTextField: Bool { payload?.mail == nil }
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
            state = .saved
            try? await Task.sleep(for: .milliseconds(1200))
            extensionContext?.completeRequest(returningItems: [])
        } catch {
            state = .failed(String(localized: "Tagwerk kann gerade nichts übernehmen."))
        }
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
