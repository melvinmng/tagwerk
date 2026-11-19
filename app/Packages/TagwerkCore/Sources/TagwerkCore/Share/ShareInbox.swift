import Foundation

/// A file to copy into the inbox; `name` is the name the user sees (a provider's temporary file may be named differently).
public struct ShareInboxSource: Sendable, Hashable {
    public var url: URL
    public var name: String
    public var typeIdentifier: String

    public init(url: URL, name: String, typeIdentifier: String) {
        self.url = url
        self.name = name
        self.typeIdentifier = typeIdentifier
    }
}

/// The folder the share extension writes and the app reads (plan P6, task 2): `<id>.json` plus a folder `<id>/` with the
/// copied files. Every write is atomic, so a reader never sees a half-written item. It never logs titles or text.
public final class ShareInbox {
    /// At most this many items wait; a new one pushes out the oldest.
    public static let maximumItems = 20
    /// Items older than this are dropped when the inbox is read.
    public static let maximumAge: TimeInterval = 14 * 24 * 3600
    /// How often the app opens the sheet of one item before it only lists it.
    public static let maximumOffers = 3
    /// A folder without a JSON file older than this is the rest of an interrupted write.
    static let orphanAge: TimeInterval = 24 * 3600

    public enum Failure: Error, Equatable {
        case unreadableSource
    }

    private let directory: URL
    private let now: () -> Date
    private let fileManager: FileManager

    public init(directory: URL, now: @escaping () -> Date = Date.init, fileManager: FileManager = .default) {
        self.directory = directory
        self.now = now
        self.fileManager = fileManager
    }

    /// `<container>/Library/Application Support/ShareInbox` of the App Group.
    public static func defaultDirectory(in container: URL) -> URL {
        container.appending(path: "Library/Application Support/ShareInbox", directoryHint: .isDirectory)
    }

    // MARK: Writing

    /// Copies the files into `<id>/`, writes `<id>.json` and keeps the inbox at `maximumItems`. Returns the item as stored
    /// (with the file entries filled in). Files are copied, never moved: the provider owns the originals.
    @discardableResult
    public func write(_ item: ShareInboxItem, copying sources: [ShareInboxSource] = []) throws -> ShareInboxItem {
        try prepareDirectory()
        makeRoom()
        var stored = item
        stored.files = []
        let folder = folderURL(for: item.id)
        do {
            if !sources.isEmpty {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
            var usedNames: Set<String> = []
            for source in sources {
                guard fileManager.isReadableFile(atPath: source.url.path) else { throw Failure.unreadableSource }
                let name = Self.uniqueName(Self.safeName(source.name), used: &usedNames)
                let target = folder.appending(path: name)
                try fileManager.copyItem(at: source.url, to: target)
                try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: target.path)
                let size = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                stored.files.append(ShareInboxFile(name: name, relativePath: "\(item.id.uuidString)/\(name)",
                                                   typeIdentifier: source.typeIdentifier, byteCount: size))
            }
            try save(stored)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return stored
    }

    /// Counts one more offer of the item; does nothing for an unknown ID.
    public func markOffered(_ id: UUID) {
        guard var item = load(id) else { return }
        item.offeredCount += 1
        try? save(item)
    }

    /// Starts the offers again ("Übernehmen" in the list of parked items); does nothing for an unknown ID.
    public func resetOffers(_ id: UUID) {
        guard var item = load(id) else { return }
        item.offeredCount = 0
        try? save(item)
    }

    /// Deletes the item and its files.
    public func remove(_ id: UUID) {
        try? fileManager.removeItem(at: jsonURL(for: id))
        try? fileManager.removeItem(at: folderURL(for: id))
    }

    // MARK: Reading

    /// All readable items, oldest first. Items that are too old, unreadable or of an unknown version are deleted.
    public func pending() -> [ShareInboxItem] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        let cutoff = now().addingTimeInterval(-Self.maximumAge)
        var items: [ShareInboxItem] = []
        var knownFolders: Set<String> = []
        for name in names where name.hasSuffix(".json") {
            let stem = String(name.dropLast(".json".count))
            knownFolders.insert(stem)
            guard let id = UUID(uuidString: stem), let item = load(id), item.version == ShareInboxItem.currentVersion,
                  item.createdAt >= cutoff else {
                try? fileManager.removeItem(at: directory.appending(path: name))
                try? fileManager.removeItem(at: directory.appending(path: stem))
                continue
            }
            items.append(item)
        }
        removeOrphanFolders(names: names, known: knownFolders)
        return items.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// The location of a copied file, if it still exists.
    public func fileURL(for file: ShareInboxFile, in item: ShareInboxItem) -> URL? {
        let url = directory.appending(path: file.relativePath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Files

    private func jsonURL(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }
    private func folderURL(for id: UUID) -> URL { directory.appending(path: id.uuidString, directoryHint: .isDirectory) }

    private func load(_ id: UUID) -> ShareInboxItem? {
        guard let data = try? Data(contentsOf: jsonURL(for: id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShareInboxItem.self, from: data)
    }

    private func save(_ item: ShareInboxItem) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        // Readable after the first unlock, so a share made from the lock screen can be read later.
        try data.write(to: jsonURL(for: item.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The inbox is a cache: no backup, readable after the first unlock.
    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    /// Drops the oldest items until one more fits.
    private func makeRoom() {
        let items = pending()
        guard items.count >= Self.maximumItems else { return }
        for item in items.prefix(items.count - Self.maximumItems + 1) { remove(item.id) }
    }

    private func removeOrphanFolders(names: [String], known: Set<String>) {
        let cutoff = now().addingTimeInterval(-Self.orphanAge)
        for name in names where !name.hasSuffix(".json") && !known.contains(name) {
            let url = directory.appending(path: name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fileManager.removeItem(at: url) }
        }
    }

    // MARK: File names

    /// A name without path parts, hidden-file dots and control characters; never empty.
    static func safeName(_ name: String) -> String {
        let last = name.split(separator: "/").last.map(String.init) ?? name
        let cleaned = last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespaces)
        while result.hasPrefix(".") { result.removeFirst() }
        return result.isEmpty ? "Datei" : String(result.prefix(120))
    }

    private static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        var candidate = name
        var counter = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while used.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
