import Foundation
import ImageIO
import PDFKit
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

    /// What an attachment is for (`NoteAttachmentRecord.roleRaw`). A scan is a PDF with a preview of its first page, a
    /// drawing is the picture of a drawing, and its strokes are the data that make it editable again.
    enum Role: String {
        case plain = ""
        case scan
        case drawing
        case strokes
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

    /// Stores generated data (a scanned PDF, the picture of a drawing, stroke data) under a name. Throws `.tooLarge` above
    /// `maximumFileBytes`. `companionOf` ties a file to the attachment it belongs to.
    @discardableResult
    func addData(_ data: Data, fileName: String, type: UTType, role: Role, to noteID: UUID, companionOf: UUID? = nil,
                 pageCount: Int = 0) throws -> NoteAttachmentRecord {
        guard data.count <= Self.maximumFileBytes else { throw Failure.tooLarge }
        return try store(data, fileName: fileName, type: type, noteID: noteID, role: role, companionOf: companionOf, pageCount: pageCount)
    }

    private func store(_ data: Data, fileName: String, type: UTType?, noteID: UUID, role: Role = .plain, companionOf: UUID? = nil,
                       pageCount: Int = 0) throws -> NoteAttachmentRecord {
        let record = NoteAttachmentRecord(noteID: noteID, fileName: fileName, typeIdentifier: type?.identifier ?? "", byteCount: data.count,
                                          createdAt: now(), roleRaw: role.rawValue, companionOfID: companionOf, pageCount: pageCount)
        try write(data, for: record)
        context.insert(record)
        save()
        return record
    }

    /// Puts a file back from a backup, with its original ID, so the references in the notes work again.
    func restore(id: UUID, noteID: UUID?, fileName: String, typeIdentifier: String, createdAt: Date, data: Data,
                 roleRaw: String = "", companionOfID: UUID? = nil, recognizedText: String? = nil, pageCount: Int = 0) throws {
        let record = NoteAttachmentRecord(id: id, noteID: noteID, fileName: fileName, typeIdentifier: typeIdentifier, byteCount: data.count,
                                          createdAt: createdAt, roleRaw: roleRaw, companionOfID: companionOfID,
                                          recognizedText: recognizedText, pageCount: pageCount)
        try write(data, for: record)
        context.insert(record)
    }

    /// Replaces the bytes of an attachment and keeps its ID, so the references in the text stay valid (a drawing that was
    /// edited). Throws `.unreadable` for an unknown attachment and `.tooLarge` above `maximumFileBytes`.
    func replaceData(_ data: Data, for id: UUID) throws {
        guard let record = record(id: id) else { throw Failure.unreadable }
        guard data.count <= Self.maximumFileBytes else { throw Failure.tooLarge }
        try write(data, for: record)
        record.byteCount = data.count
        thumbnails.removeAllObjects()
        versions[id, default: 0] += 1
        save()
    }

    /// Gives an attachment another name. The extension stays, because the stored file is named by ID and extension; a name
    /// without text, or one with only separators, changes nothing.
    func rename(_ id: UUID, to name: String) {
        guard let record = record(id: id) else { return }
        let ext = URL(fileURLWithPath: record.fileName).pathExtension.lowercased()
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if !ext.isEmpty, (base as NSString).pathExtension.lowercased() == ext { base = (base as NSString).deletingPathExtension }
        guard !base.isEmpty else { return }
        record.fileName = ext.isEmpty ? base : "\(base).\(ext)"
        save()
    }

    /// Stores the text recognised in a scan; the empty text says that recognition ran and found nothing.
    func setRecognizedText(_ text: String, for id: UUID) {
        guard let record = record(id: id) else { return }
        record.recognizedText = text
        save()
    }

    /// Marks a scan as not recognised yet, before a new try.
    func setRecognizedTextPending(for id: UUID) {
        guard let record = record(id: id) else { return }
        record.recognizedText = nil
        save()
    }

    /// The file of the given role that belongs to an attachment (the strokes of a drawing).
    func companion(of id: UUID, role: Role) -> NoteAttachmentRecord? {
        records().first { $0.companionOfID == id && $0.roleRaw == role.rawValue }
    }

    /// Copies attachments for another note: each one gets a new record (new ID, same name, type, role, page count, recognised
    /// text and date) and a copy of its file with the same file protection as `write`, and so does each file that belongs to
    /// it (the strokes of a drawing), tied to the new attachment. An attachment without a record or without a file is left
    /// out. Returns old ID → new ID.
    @discardableResult
    func duplicate(ids: [UUID], to noteID: UUID) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        let all = records()
        for id in ids where mapping[id] == nil {
            guard let source = all.first(where: { $0.id == id }), let data = data(for: id) else { continue }
            let copy = NoteAttachmentRecord(noteID: noteID, fileName: source.fileName, typeIdentifier: source.typeIdentifier,
                                            byteCount: data.count, createdAt: source.createdAt, roleRaw: source.roleRaw,
                                            recognizedText: source.recognizedText, pageCount: source.pageCount)
            guard (try? write(data, for: copy)) != nil else { continue }
            context.insert(copy)
            mapping[id] = copy.id
            for companion in all where companion.companionOfID == id {
                guard let companionData = self.data(for: companion.id) else { continue }
                let companionCopy = NoteAttachmentRecord(noteID: noteID, fileName: companion.fileName, typeIdentifier: companion.typeIdentifier,
                                                         byteCount: companionData.count, createdAt: companion.createdAt, roleRaw: companion.roleRaw,
                                                         companionOfID: copy.id, recognizedText: companion.recognizedText, pageCount: companion.pageCount)
                guard (try? write(companionData, for: companionCopy)) != nil else { continue }
                context.insert(companionCopy)
            }
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

    /// Name, formatted size and kind of every attachment of a note, for the rendered page. Files that belong to another
    /// attachment (the strokes of a drawing) are not shown.
    func displays(of noteID: UUID) -> [UUID: NoteAttachmentDisplay] {
        attachments(of: noteID).filter { !$0.isCompanion }.reduce(into: [:]) { result, record in
            let isImage = UTType(record.typeIdentifier)?.conforms(to: .image) == true
            let size = ByteCountFormatter.string(fromByteCount: Int64(record.byteCount), countStyle: .file)
            if record.roleRaw == Role.drawing.rawValue {
                result[record.id] = NoteAttachmentDisplay(name: record.fileName, detail: size, kind: .drawing, version: versions[record.id] ?? 0)
            } else if record.roleRaw == Role.scan.rawValue {
                result[record.id] = NoteAttachmentDisplay(name: record.fileName,
                                                          detail: Self.scanDetail(pages: record.pageCount, size: size, recognizedText: record.recognizedText),
                                                          kind: .scan(pages: record.pageCount))
            } else {
                result[record.id] = NoteAttachmentDisplay(name: record.fileName, detail: size, kind: isImage ? .image : .file)
            }
        }
    }

    /// "8 Seiten · 3,1 MB · PDF · Text erkannt": the line under the name of a scan. Recognition that has not run yet says so;
    /// recognition that found nothing (or failed) says nothing, the menu of the scan offers a new try.
    static func scanDetail(pages: Int, size: String, recognizedText: String?) -> String {
        var parts: [String] = []
        if pages == 1 { parts.append(String(localized: "1 Seite")) } else if pages > 1 { parts.append(String(localized: "\(pages) Seiten")) }
        parts.append(size)
        parts.append("PDF")
        switch recognizedText {
        case nil: parts.append(String(localized: "Text wird erkannt …"))
        case let text? where !text.isEmpty: parts.append(String(localized: "Text erkannt"))
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// The text recognised in the scans a note's text refers to, one paragraph per scan, for the app search. Empty for a note
    /// without a recognised scan. It is the attachment's text, not the note's: it never goes to the assistant.
    static func scanText(text: String, index: [UUID: NoteAttachmentRecord]) -> String {
        MarkdownText.attachmentReferences(in: text).compactMap { id -> String? in
            guard let record = index[id], record.roleRaw == Role.scan.rawValue, let recognized = record.recognizedText, !recognized.isEmpty else { return nil }
            return recognized
        }.joined(separator: "\n\n")
    }

    /// The scans of a note that recognition has not looked at yet (a run that was cut short by closing the app).
    func scansAwaitingRecognition(of noteID: UUID) -> [UUID] {
        attachments(of: noteID).filter { $0.roleRaw == Role.scan.rawValue && $0.recognizedText == nil }.map(\.id)
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

    /// Files that belong to another attachment are never counted; a scan counts as a picture, because its first page is its
    /// preview.
    static func cardInfo(text: String, index: [UUID: NoteAttachmentRecord]) -> CardInfo {
        var info = CardInfo()
        for id in MarkdownText.attachmentReferences(in: text) {
            guard let record = index[id], !record.isCompanion else { continue }
            if record.roleRaw == Role.scan.rawValue || UTType(record.typeIdentifier)?.conforms(to: .image) == true {
                if info.firstImageID == nil { info.firstImageID = id }
            } else {
                info.fileCount += 1
            }
        }
        return info
    }

    private let thumbnails = NSCache<NSString, UIImage>()
    /// How often the bytes of an attachment were replaced in this session; it goes into the address of the picture on the page.
    private var versions: [UUID: Int] = [:]

    /// A small picture of an attachment for a list card; read through ImageIO, so the full picture is never decoded. For a
    /// PDF it is the first page.
    func thumbnail(for id: UUID, edge: CGFloat = 96) -> UIImage? {
        let key = "\(id.uuidString)-\(Int(edge))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        if let record = record(id: id), UTType(record.typeIdentifier)?.conforms(to: .pdf) == true {
            guard let url = url(for: id), let page = Self.firstPage(ofPDFAt: url, edge: edge) else { return nil }
            thumbnails.setObject(page, forKey: key)
            return page
        }
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

    /// The first page of a PDF as a picture whose longer side is `edge` pixels.
    static func firstPage(ofPDFAt url: URL, edge: CGFloat) -> UIImage? {
        PDFDocument(url: url)?.page(at: 0).flatMap { render($0, edge: edge) }
    }

    /// One page of a PDF as a picture on white, exactly `edge` pixels on its longer side, whatever the screen scale is.
    nonisolated static func render(_ page: PDFPage, edge: CGFloat) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = edge / max(bounds.width, bounds.height)
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            thumbnail.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The files of the attachments a note's text refers to, for "Anhänge teilen", under their own names. Files that belong
    /// to another attachment (the strokes of a drawing) stay out.
    func shareableURLs(of noteID: UUID, text: String) -> [URL] {
        let referenced = MarkdownText.attachmentIDs(in: text)
        return attachments(of: noteID).filter { referenced.contains($0.id) && !$0.isCompanion }.compactMap { exportURL(for: $0.id) }
    }

    /// Number and total size of all attachments (for the backup page).
    var summary: (count: Int, bytes: Int) {
        let all = records()
        return (all.count, all.reduce(0) { $0 + $1.byteCount })
    }

    // MARK: Removing

    /// Removes attachments, their files first, and the files that belong to them (the strokes of a drawing).
    func delete(ids: some Collection<UUID>) {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        for record in records() where wanted.contains(record.id) || record.companionOfID.map(wanted.contains) == true {
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
    /// A file that belongs to another attachment counts as referenced exactly when that attachment is, and goes with it; one
    /// whose attachment does not exist any more goes too.
    func removeUnreferenced(noteID: UUID, text: String) {
        let referenced = MarkdownText.attachmentIDs(in: text)
        let mine = attachments(of: noteID)
        let existing = Set(mine.map(\.id))
        let unreferenced = mine.filter { record in
            if let owner = record.companionOfID { return !(existing.contains(owner) && referenced.contains(owner)) }
            return !referenced.contains(record.id)
        }
        delete(ids: unreferenced.map(\.id))
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
