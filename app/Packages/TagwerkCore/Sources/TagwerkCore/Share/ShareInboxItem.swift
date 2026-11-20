import Foundation

/// A file the extension copied next to the item; `relativePath` is relative to the inbox folder.
public struct ShareInboxFile: Sendable, Hashable, Codable {
    public var name: String
    public var relativePath: String
    public var typeIdentifier: String
    public var byteCount: Int

    public init(name: String, relativePath: String, typeIdentifier: String, byteCount: Int) {
        self.name = name
        self.relativePath = relativePath
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
    }
}

/// One shared item waiting in the inbox until the app opens its sheet. The extension writes it, the app reads and
/// removes it. Nothing here is a task or a note yet: that happens only when the user confirms in the app.
public struct ShareInboxItem: Sendable, Hashable, Codable, Identifiable {
    /// Raised when the format changes in a way old readers cannot handle; unknown versions are dropped.
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var createdAt: Date
    public var target: ShareTarget
    public var title: String
    public var text: String?
    public var url: URL?
    /// The title of the web page a link came from (Safari); `nil` for items that carry none, also for older ones.
    public var pageTitle: String?
    public var files: [ShareInboxFile]
    public var mail: MailMessage?
    /// How often the app opened the sheet for this item; after `ShareInbox.maximumOffers` it is only listed.
    public var offeredCount: Int

    public init(id: UUID = UUID(), createdAt: Date, target: ShareTarget, title: String, text: String? = nil, url: URL? = nil,
                pageTitle: String? = nil, files: [ShareInboxFile] = [], mail: MailMessage? = nil, offeredCount: Int = 0) {
        self.version = Self.currentVersion
        self.id = id
        self.createdAt = createdAt
        self.target = target
        self.title = title
        self.text = text
        self.url = url
        self.pageTitle = pageTitle
        self.files = files
        self.mail = mail
        self.offeredCount = offeredCount
    }
}
