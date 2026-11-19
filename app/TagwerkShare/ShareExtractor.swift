import Foundation
import OSLog
import TagwerkCore
import UniformTypeIdentifiers

/// What the extractor read from the share sheet. The files lie in `directory`, a temporary folder the caller removes.
struct ExtractedShare {
    var parts: [SharePart]
    var files: [ShareInboxSource]
    var mail: MailMessage?
    var directory: URL
}

enum ShareExtractionError: Error {
    case tooLarge
    case nothingShared
}

/// Reads `NSItemProvider`s into `SharePart`s (plan P6, task 4). Files are copied inside the provider's callback, because the
/// URL it hands out only lives there, and never loaded into memory: the extension is stopped at about 120 MB. A mail file is
/// read only as far as its text (the first `mailReadBytes`), then parsed and dropped.
@MainActor
enum ShareExtractor {
    nonisolated static let maximumFileBytes = 25 * 1024 * 1024
    nonisolated static let mailReadBytes = 2_000_000
    private nonisolated static let log = Logger(subsystem: "local.tagwerk.share", category: "extract")

    static func extract(from items: [NSExtensionItem]) async throws -> ExtractedShare {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ShareExtract-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var result = ExtractedShare(parts: [], files: [], mail: nil, directory: directory)
        do {
            for item in items {
                for provider in item.attachments ?? [] {
                    try await read(provider, into: &result)
                }
                // Safari delivers the page title or the selected text here.
                if let text = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                   !result.parts.contains(where: { $0 == .text(text) }) {
                    result.parts.append(.text(text))
                }
            }
            guard !result.parts.isEmpty else { throw ShareExtractionError.nothingShared }
            return result
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: Providers

    private static func read(_ provider: NSItemProvider, into result: inout ExtractedShare) async throws {
        let types = provider.registeredTypeIdentifiers
        #if DEBUG
        // Type identifiers only, never content (spike S2).
        log.debug("provider types: \(types.joined(separator: ", "), privacy: .public)")
        #endif
        let known = types.compactMap { identifier in UTType(identifier).map { (identifier, $0) } }

        if let file = known.first(where: { isFileType($0.1) }) {
            try await readFile(provider, typeIdentifier: file.0, into: &result)
        } else if known.contains(where: { $0.1.conforms(to: .fileURL) }) {
            try await readFileURL(provider, into: &result)
        } else if known.contains(where: { $0.1.conforms(to: .url) }) {
            if let url = await loadURL(provider) { result.parts.append(.url(url)) }
        } else if known.contains(where: { $0.1.conforms(to: .text) }) {
            if let text = await loadString(provider) { result.parts.append(.text(text)) }
        }
    }

    /// A type that is a document of its own: not text, not a link, not a property list the host app adds.
    private static func isFileType(_ type: UTType) -> Bool {
        guard type.conforms(to: .data) || type.conforms(to: .content) else { return false }
        return !type.conforms(to: .text) && !type.conforms(to: .url) && !type.conforms(to: .propertyList)
    }

    private static func readFile(_ provider: NSItemProvider, typeIdentifier: String, into result: inout ExtractedShare) async throws {
        let copied = try await copyFile(provider, typeIdentifier: typeIdentifier, into: result.directory)
        try register(copied, typeIdentifier: typeIdentifier, into: &result)
    }

    /// A file shared as a link to a file (Files app).
    private static func readFileURL(_ provider: NSItemProvider, into result: inout ExtractedShare) async throws {
        guard let url = await loadURL(provider), url.isFileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let copied = try copyFile(at: url, into: result.directory)
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? UTType.data.identifier
        try register(copied, typeIdentifier: type, into: &result)
    }

    private static func register(_ copied: CopiedFile, typeIdentifier: String, into result: inout ExtractedShare) throws {
        let isMail = UTType(typeIdentifier)?.conforms(to: .emailMessage) == true || typeIdentifier == "com.apple.mail.email"
            || (copied.name as NSString).pathExtension.lowercased() == "eml"
        if isMail, result.mail == nil, let handle = try? FileHandle(forReadingFrom: copied.url) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: mailReadBytes), let mail = MailMessageParser.parse(data) {
                result.mail = mail
                // The mail itself is kept as text; the file is not needed any more.
                try? FileManager.default.removeItem(at: copied.url)
                result.parts.append(.file(typeIdentifier: typeIdentifier, name: copied.name, byteCount: copied.size))
                return
            }
        }
        result.parts.append(.file(typeIdentifier: typeIdentifier, name: copied.name, byteCount: copied.size))
        result.files.append(ShareInboxSource(url: copied.url, name: copied.name, typeIdentifier: typeIdentifier))
    }

    // MARK: Loading

    private struct CopiedFile: Sendable {
        var url: URL
        var name: String
        var size: Int
    }

    private static func copyFile(_ provider: NSItemProvider, typeIdentifier: String, into directory: URL) async throws -> CopiedFile {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? ShareExtractionError.nothingShared)
                    return
                }
                // Inside the callback: the system removes the file when it returns.
                do {
                    continuation.resume(returning: try copyFile(at: url, into: directory))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func copyFile(at source: URL, into directory: URL) throws -> CopiedFile {
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maximumFileBytes else { throw ShareExtractionError.tooLarge }
        // One folder per file keeps equal names apart; the inbox makes the final names unique.
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.lastPathComponent.isEmpty ? "Datei" : source.lastPathComponent
        let target = folder.appending(path: name)
        try FileManager.default.copyItem(at: source, to: target)
        #if DEBUG
        log.debug("copied file, \(size, privacy: .public) bytes")
        #endif
        return CopiedFile(url: target, name: name, size: size)
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func loadString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }
    }
}
