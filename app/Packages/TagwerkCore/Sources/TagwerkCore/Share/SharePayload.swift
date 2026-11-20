import Foundation
import UniformTypeIdentifiers

/// Where a shared item goes in Tagwerk.
public enum ShareTarget: String, Sendable, Hashable, Codable, CaseIterable {
    case task, note, shopping, recipe, mailTask
}

/// One piece of what an app handed to the share sheet, as the extension reads it.
public enum SharePart: Sendable, Hashable {
    case text(String)
    case url(URL)
    /// The title of the web page a share came from (the Safari preprocessing script delivers it): the text of a link to it.
    case pageTitle(String)
    /// A file already copied by the extension. `typeIdentifier` is the UTI the provider registered.
    case file(typeIdentifier: String, name: String, byteCount: Int)
}

/// What a share sheet delivered, classified without any UI (plan P6, task 1). Pure rules; no logging of content.
public struct SharePayload: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case url, text, image, file, mail
    }

    public var kind: Kind
    public var title: String
    public var text: String?
    public var url: URL?
    /// The title of the web page the item came from, when the sender told it (Safari). The title of the item can be the
    /// first line of a selection instead.
    public var pageTitle: String?
    public var fileNames: [String]
    /// Set by the extension after it parsed a shared `.eml`; the classification only recognizes the file.
    public var mail: MailMessage?

    public static let maximumTitleLength = 120

    public init(kind: Kind, title: String, text: String? = nil, url: URL? = nil, pageTitle: String? = nil, fileNames: [String] = [],
                mail: MailMessage? = nil) {
        self.kind = kind
        self.title = title
        self.text = text
        self.url = url
        self.pageTitle = pageTitle
        self.fileNames = fileNames
        self.mail = mail
    }

    // MARK: Classification

    /// Classifies the parts. `nil` when nothing usable was shared (no parts, or only white space).
    public static func classify(_ parts: [SharePart]) -> SharePayload? {
        var texts: [String] = []
        var webURL: URL?
        var pageTitle: String?
        var files: [(type: String, name: String)] = []
        for part in parts {
            switch part {
            case .text(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts.append(trimmed) }
            case .url(let value):
                if webURL == nil, isWebURL(value) { webURL = value }
            case .pageTitle(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if pageTitle == nil, !trimmed.isEmpty { pageTitle = trimmed }
            case .file(let type, let name, _):
                files.append((type, name))
            }
        }
        texts = ShareItemText.mergeTexts(texts)
        let fileNames = files.map(\.name)

        // 1. A mail file wins over everything shared with it.
        if files.contains(where: { isMail(type: $0.type, name: $0.name) }) {
            let name = files.first { isMail(type: $0.type, name: $0.name) }?.name ?? ""
            let base = (name as NSString).deletingPathExtension
            return SharePayload(kind: .mail, title: cut(base), fileNames: fileNames)
        }
        // 2. A web link. The title is the page title if Safari told it, else the first line of the text shared with it. The text
        // (a selection, or the page title Safari adds as text) is the body once; it is never also a second text.
        if let webURL {
            let link = webURL.absoluteString
            let extra = texts.filter { $0 != link && $0 != pageTitle }
            let joined = extra.isEmpty ? nil : extra.joined(separator: "\n")
            let title = pageTitle ?? joined.flatMap(firstLine) ?? host(of: webURL)
            return SharePayload(kind: .url, title: cut(title), text: joined, url: webURL, pageTitle: pageTitle.map(cut),
                                fileNames: fileNames)
        }
        // 3. Files: the first one decides for mixed content.
        if let first = files.first {
            let isImage = UTType(first.type)?.conforms(to: .image) == true
            let title = (first.name as NSString).deletingPathExtension
            let joined = texts.isEmpty ? nil : texts.joined(separator: "\n")
            return SharePayload(kind: isImage ? .image : .file, title: cut(title.isEmpty ? first.name : title), text: joined,
                                fileNames: fileNames)
        }
        // 4. Text; the title is its first non-empty line.
        guard !texts.isEmpty else { return nil }
        let joined = texts.joined(separator: "\n")
        return SharePayload(kind: .text, title: cut(firstLine(joined) ?? joined), text: joined)
    }

    /// The target Tagwerk proposes; the user can change it in the extension.
    public var suggestedTarget: ShareTarget {
        switch kind {
        case .mail: return .mailTask
        case .image, .file: return .note
        case .url:
            guard let url else { return .task }
            return Self.looksLikeRecipe(url: url, title: title) ? .recipe : .task
        case .text:
            let lines = (text ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let isShort = (1...3).contains(lines.count) && lines.allSatisfy { $0.count <= Self.maximumShoppingLineLength }
            return isShort ? .shopping : .note
        }
    }

    /// The targets the picker offers, the most likely first. "Mail zu Aufgabe" is offered for mails and for text, because
    /// markdown or a mail marked in the Mail app arrives as plain text. A file can only be attached to a note; for a task
    /// the extension says so.
    public var availableTargets: [ShareTarget] {
        switch kind {
        case .mail: [.mailTask, .task, .note]
        case .url: [.task, .note, .recipe]
        case .text: [.task, .note, .shopping, .recipe, .mailTask]
        case .image: [.note, .task, .recipe]
        case .file: [.note, .task]
        }
    }

    static let maximumShoppingLineLength = 40
    private static let recipeKeywords = ["rezept", "recipe", "chefkoch"]

    static func looksLikeRecipe(url: URL, title: String) -> Bool {
        let haystack = [url.host(percentEncoded: false) ?? "", url.path(percentEncoded: false), title].joined(separator: " ").lowercased()
        return recipeKeywords.contains { haystack.contains($0) }
    }

    // MARK: Helpers

    private static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && url.host(percentEncoded: false) != nil
    }

    private static func isMail(type: String, name: String) -> Bool {
        if let uti = UTType(type), uti.conforms(to: .emailMessage) { return true }
        if type == "com.apple.mail.email" { return true }
        return (name as NSString).pathExtension.lowercased() == "eml"
    }

    private static func host(of url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    private static func cut(_ text: String) -> String {
        text.count > maximumTitleLength ? String(text.prefix(maximumTitleLength)) : text
    }
}
