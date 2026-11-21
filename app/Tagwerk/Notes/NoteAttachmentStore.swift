import Foundation
import ImageIO
import SwiftData
import TagwerkCore
import UIKit
import UniformTypeIdentifiers

/// Pictures and files attached to notes. Metadata lies in `NoteAttachmentRecord`, the bytes in one folder on this
/// device (`Application Support/NoteAttachments/<id>.<ext>`, written with complete file protection). The only place
/// that writes either. Nothing here leaves the device; the sharing sheet and the backup are the user's own actions.
@MainActor
final class NoteAttachmentStore {
    /// The largest file that can be attached.
    static let maximumFileBytes = 25 * 1024 * 1024
    /// Pictures are scaled down to this edge length (in pixels) and stored as JPEG.
    static let maximumImageEdge: CGFloat = 2048
    static let imageQuality: CGFloat = 0.8

    enum Failure: Error, Equatable {
        case tooLarge
        case unreadable
        case notAnImage
    }

    private let context: ModelContext
    private let directory: URL
    private let now: () -> Date
    private let fileManager = FileManager.default

    /// `directory` is injectable so tests use a temporary folder.
    init(context: ModelContext, directory: URL = NoteAttachmentStore.defaultDirectory, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.directory = directory
        self.now = now
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "NoteAttachments", directoryHint: .isDirectory)
    }

    // MARK: Adding

    /// Stores a picture as JPEG, at most `maximumImageEdge` pixels on its longer side. Transparency is lost.
    @discardableResult
    func addImage(_ image: UIImage, to noteID: UUID, name: String = "Foto") throws -> NoteAttachmentRecord {
        guard let data = ImageDownscaler.jpeg(from: image, maxEdge: Self.maximumImageEdge, quality: Self.imageQuality) else { throw Failure.notAnImage }
        return try store(data, fileName: Self.fileName(name, extension: "jpg"), type: UTType.jpeg, noteID: noteID)
    }

    /// Stores the picture in image data (a photo from the library, the clipboard).
    @discardableResult
    func addImage(data: Data, to noteID: UUID, name: String = "Foto") throws -> NoteAttachmentRecord {
        guard let image = UIImage(data: data) else { throw Failure.notAnImage }
        return try addImage(image, to: noteID, name: name)
    }

    /// Copies a file into the store. `url` may be outside the app (the file importer hands out security-scoped URLs).
    /// Throws `.tooLarge` above `maximumFileBytes`.
    @discardableResult
    func addFile(at url: URL, to noteID: UUID) throws -> NoteAttachmentRecord {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= Self.maximumFileBytes else { throw Failure.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        guard data.count <= Self.maximumFileBytes else { throw Failure.tooLarge }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return try store(data, fileName: url.lastPathComponent, type: type, noteID: noteID)
    }

    private func store(_ data: Data, fileName: String, type: UTType?, noteID: UUID) throws -> NoteAttachmentRecord {
        let record = NoteAttachmentRecord(noteID: noteID, fileName: fileName, typeIdentifier: type?.identifier ?? "", byteCount: data.count,
                                          createdAt: now())
        try write(data, for: record)
        context.insert(record)
        save()
        return record
    }

    /// Puts a file back from a backup, with its original ID, so the references in the notes work again.
    func restore(id: UUID, noteID: UUID?, fileName: String, typeIdentifier: String, createdAt: Date, data: Data) throws {
        let record = NoteAttachmentRecord(id: id, noteID: noteID, fileName: fileName, typeIdentifier: typeIdentifier, byteCount: data.count,
                                          createdAt: createdAt)
        try write(data, for: record)
        context.insert(record)
    }

    /// Copies attachments for another note: each one gets a new record (new ID, same name, type and date) and a copy of its
    /// file with the same file protection as `write`. An attachment without a record or without a file is left out.
    /// Returns old ID → new ID.
    @discardableResult
    func duplicate(ids: [UUID], to noteID: UUID) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for id in ids where mapping[id] == nil {
            guard let source = record(id: id), let data = data(for: id) else { continue }
            let copy = NoteAttachmentRecord(noteID: noteID, fileName: source.fileName, typeIdentifier: source.typeIdentifier,
                                            byteCount: data.count, createdAt: source.createdAt)
            guard (try? write(data, for: copy)) != nil else { continue }
            context.insert(copy)
            mapping[id] = copy.id
        }
        if !mapping.isEmpty { save() }
        return mapping
    }

    // MARK: Reading

    func records() -> [NoteAttachmentRecord] {
        (try? context.fetch(FetchDescriptor<NoteAttachmentRecord>())) ?? []
    }

    func attachments(of noteID: UUID) -> [NoteAttachmentRecord] {
        records().filter { $0.noteID == noteID }.sorted { $0.createdAt < $1.createdAt }
    }

    func record(id: UUID) -> NoteAttachmentRecord? {
        records().first { $0.id == id }
    }

    /// The file of an attachment, if the record and the file exist.
    func url(for id: UUID) -> URL? {
        guard let record = record(id: id) else { return nil }
        let url = fileURL(for: record)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// The pictures and files a note's text refers to, for its card in a list: the first picture and the number of files.
    /// `records` is `index()` of one fetch for the whole list.
    struct CardInfo: Equatable {
        var firstImageID: UUID?
        var fileCount = 0
    }

    func index() -> [UUID: NoteAttachmentRecord] {
        Dictionary(records().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func cardInfo(text: String, index: [UUID: NoteAttachmentRecord]) -> CardInfo {
        var info = CardInfo()
        for id in MarkdownText.attachmentReferences(in: text) {
            guard let record = index[id] else { continue }
            if UTType(record.typeIdentifier)?.conforms(to: .image) == true {
                if info.firstImageID == nil { info.firstImageID = id }
            } else {
                info.fileCount += 1
            }
        }
        return info
    }

    private let thumbnails = NSCache<NSString, UIImage>()

    /// A small picture of an attachment for a list card; read through ImageIO, so the full picture is never decoded.
    func thumbnail(for id: UUID, edge: CGFloat = 96) -> UIImage? {
        let key = "\(id.uuidString)-\(Int(edge))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let url = url(for: id), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: edge]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let result = UIImage(cgImage: image)
        thumbnails.setObject(result, forKey: key)
        return result
    }

    /// A copy of the file under its own name in a temporary folder, for Quick Look and the share sheet (the stored file is
    /// named by its ID). The system cleans the folder up.
    func exportURL(for id: UUID) -> URL? {
        guard let source = url(for: id), let record = record(id: id) else { return nil }
        let folder = fileManager.temporaryDirectory.appending(path: "NoteAttachmentExports/\(id.uuidString)", directoryHint: .isDirectory)
        let target = folder.appending(path: record.fileName.isEmpty ? source.lastPathComponent : record.fileName)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: target)
        do { try fileManager.copyItem(at: source, to: target) } catch { return nil }
        return target
    }

    func data(for id: UUID) -> Data? {
        url(for: id).flatMap { try? Data(contentsOf: $0) }
    }

    /// Number and total size of all attachments (for the backup page).
    var summary: (count: Int, bytes: Int) {
        let all = records()
        return (all.count, all.reduce(0) { $0 + $1.byteCount })
    }

    // MARK: Removing

    /// Removes attachments, their files first.
    func delete(ids: some Collection<UUID>) {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        for record in records() where wanted.contains(record.id) {
            try? fileManager.removeItem(at: fileURL(for: record))
            context.delete(record)
        }
        save()
    }

    /// Removes every attachment of a note, e.g. when the note is deleted for good.
    func deleteAll(of noteID: UUID) {
        delete(ids: attachments(of: noteID).map(\.id))
    }

    /// Removes the attachments of a note whose reference is no longer in `text`. The editor calls it when it closes, so an
    /// attachment goes only after the user deleted its reference, not while they are still editing.
    func removeUnreferenced(noteID: UUID, text: String) {
        let referenced = MarkdownText.attachmentIDs(in: text)
        delete(ids: attachments(of: noteID).map(\.id).filter { !referenced.contains($0) })
    }

    /// Removes attachments whose note does not exist any more (live or in the trash) and files without a record. Without a
    /// single note, or without a single record, it removes nothing: that looks like a store that did not load, not like
    /// orphans, and the files are the only copy.
    func purgeOrphans(existingNoteIDs: Set<UUID>) {
        guard !existingNoteIDs.isEmpty else { return }
        let orphans = records().filter { record in record.noteID.map { !existingNoteIDs.contains($0) } ?? true }.map(\.id)
        delete(ids: orphans)
        guard !records().isEmpty else { return }
        let known = Set(records().map { fileURL(for: $0).lastPathComponent })
        let files = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !known.contains(file) { try? fileManager.removeItem(at: directory.appending(path: file)) }
    }

    // MARK: Files

    private func fileURL(for record: NoteAttachmentRecord) -> URL {
        let ext = URL(fileURLWithPath: record.fileName).pathExtension.lowercased()
        let name = ext.isEmpty ? record.id.uuidString : "\(record.id.uuidString).\(ext)"
        return directory.appending(path: name)
    }

    private func write(_ data: Data, for record: NoteAttachmentRecord) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: record), options: [.atomic, .completeFileProtection])
    }

    private func save() {
        try? context.save()
    }

    /// "Foto.jpg": the name without a path and with the extension of the stored file.
    private static func fileName(_ name: String, extension ext: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? "Foto" : base) + "." + ext
    }
}
