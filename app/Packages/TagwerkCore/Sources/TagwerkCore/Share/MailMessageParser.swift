import Foundation

/// Reads the headers and the text of a `.eml` file (RFC 5322 with MIME). Only what Tagwerk needs: subject, sender,
/// date, message ID and the readable text. It never throws and never crashes on broken input; unreadable parts stay empty.
public enum MailMessageParser {
    /// The longest body kept; the request to ChatGPT is cut much shorter (`MailTaskSuggestion.maximumInputLength`).
    public static let maximumBodyLength = 60_000
    private static let maximumDepth = 3

    /// `nil` when the data is not a mail: no usable header at all.
    public static func parse(_ data: Data) -> MailMessage? {
        guard !data.isEmpty, let raw = decodeText(data) else { return nil }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let entity = Entity(text: text)
        let known = ["subject", "from", "date", "message-id", "content-type", "mime-version"]
        guard known.contains(where: { entity.headers[$0] != nil }) else { return nil }

        let subject = entity.headers["subject"].map(decodeWords) ?? ""
        let (name, address) = entity.headers["from"].map(parseSender) ?? (nil, nil)
        let body = bodyText(of: entity, depth: 0) ?? ""
        return MailMessage(subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                           senderName: name, senderAddress: address,
                           date: entity.headers["date"].flatMap(parseDate),
                           messageID: entity.headers["message-id"].flatMap(parseMessageID),
                           bodyText: String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumBodyLength)))
    }

    // MARK: Entities

    /// One MIME entity: unfolded headers (lower-cased names) and the raw body.
    private struct Entity {
        var headers: [String: String] = [:]
        var body: String

        init(text: String) {
            let lines = text.components(separatedBy: "\n")
            var headerLines: [String] = []
            var index = 0
            while index < lines.count, !lines[index].isEmpty {
                headerLines.append(lines[index])
                index += 1
            }
            body = index < lines.count ? lines[(index + 1)...].joined(separator: "\n") : ""
            var unfolded: [String] = []
            for line in headerLines {
                if let first = line.first, first == " " || first == "\t", !unfolded.isEmpty {
                    unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
                } else {
                    unfolded.append(line)
                }
            }
            for line in unfolded {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, headers[name] == nil { headers[name] = value }
            }
        }
    }

    private struct ContentType {
        var mediaType = "text/plain"
        var parameters: [String: String] = [:]

        init(_ header: String?) {
            guard let header else { return }
            let parts = header.split(separator: ";", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = parts.first, !first.isEmpty { mediaType = first.lowercased() }
            for part in parts.dropFirst() {
                guard let equals = part.firstIndex(of: "=") else { continue }
                let key = part[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
                var value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
                parameters[key] = value
            }
        }
    }

    /// The readable text of an entity: `text/plain` first, else `text/html` without tags. Attachments are skipped.
    private static func bodyText(of entity: Entity, depth: Int) -> String? {
        let type = ContentType(entity.headers["content-type"])
        if (entity.headers["content-disposition"] ?? "").lowercased().hasPrefix("attachment") { return nil }
        if type.mediaType.hasPrefix("multipart/") {
            guard depth < maximumDepth, let boundary = type.parameters["boundary"], !boundary.isEmpty else { return nil }
            let parts = splitMultipart(entity.body, boundary: boundary).map(Entity.init(text:))
            var plain: String?
            var html: String?
            for part in parts {
                let partType = ContentType(part.headers["content-type"]).mediaType
                if partType.hasPrefix("multipart/") {
                    // A nested alternative (mixed → alternative) holds the text.
                    if let nested = bodyText(of: part, depth: depth + 1), plain == nil { plain = nested }
                } else if partType == "text/plain", plain == nil {
                    plain = bodyText(of: part, depth: depth + 1)
                } else if partType == "text/html", html == nil {
                    html = bodyText(of: part, depth: depth + 1)
                }
            }
            return plain ?? html
        }
        guard type.mediaType == "text/plain" || type.mediaType == "text/html" else { return nil }
        let decoded = decodeTransfer(entity.body, encoding: entity.headers["content-transfer-encoding"], charset: type.parameters["charset"])
        return type.mediaType == "text/html" ? RecipeText.plainText(fromHTML: decoded) : decoded
    }

    private static func splitMultipart(_ body: String, boundary: String) -> [String] {
        let delimiter = "--" + boundary
        var parts: [String] = []
        var current: [String]?
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == delimiter {
                if let current { parts.append(current.joined(separator: "\n")) }
                current = []
            } else if trimmed == delimiter + "--" {
                if let current { parts.append(current.joined(separator: "\n")) }
                current = nil
                break
            } else {
                current?.append(line)
            }
        }
        if let current { parts.append(current.joined(separator: "\n")) }
        return parts
    }

    // MARK: Transfer encodings

    /// UTF-8 first, also when a read cut the last character in two (up to three bytes are dropped); else Latin-1.
    private static func decodeText(_ data: Data) -> String? {
        for dropped in 0...3 where data.count > dropped {
            if let text = String(data: data.dropLast(dropped), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func decodeTransfer(_ body: String, encoding: String?, charset: String?) -> String {
        let encoding = encoding?.trimmingCharacters(in: .whitespaces).lowercased()
        switch encoding {
        case "quoted-printable":
            return string(from: quotedPrintableBytes(body), charset: charset)
        case "base64":
            let compact = body.filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: compact, options: .ignoreUnknownCharacters) else { return "" }
            return string(from: data, charset: charset)
        default:
            return body
        }
    }

    private static func quotedPrintableBytes(_ body: String) -> Data {
        var bytes = Data()
        let lines = body.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var content = Array(line.utf8)
            var softBreak = false
            if content.last == UInt8(ascii: "=") {
                content.removeLast()
                softBreak = true
            }
            var position = 0
            while position < content.count {
                let byte = content[position]
                if byte == UInt8(ascii: "="), position + 2 < content.count, let high = hexValue(content[position + 1]),
                   let low = hexValue(content[position + 2]) {
                    bytes.append(UInt8(high * 16 + low))
                    position += 3
                } else {
                    bytes.append(byte)
                    position += 1
                }
            }
            if !softBreak, index < lines.count - 1 { bytes.append(UInt8(ascii: "\n")) }
        }
        return bytes
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "A")...UInt8(ascii: "F"): Int(byte - UInt8(ascii: "A")) + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): Int(byte - UInt8(ascii: "a")) + 10
        default: nil
        }
    }

    private static func string(from data: Data, charset: String?) -> String {
        if let encoding = stringEncoding(charset), let value = String(data: data, encoding: encoding) { return value }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func stringEncoding(_ charset: String?) -> String.Encoding? {
        guard let charset = charset?.trimmingCharacters(in: .whitespaces), !charset.isEmpty else { return nil }
        let converted = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard converted != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(converted))
    }

    // MARK: Headers

    /// Decodes RFC 2047 encoded words (`=?utf-8?B?…?=`, `=?iso-8859-1?Q?…?=`). White space between two encoded words is dropped.
    static func decodeWords(_ value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        var result = ""
        var cursor = value.startIndex
        var lastWasEncoded = false
        for match in encodedWord.matches(in: value, range: range) {
            guard let whole = Range(match.range, in: value), let charsetRange = Range(match.range(at: 1), in: value),
                  let kindRange = Range(match.range(at: 2), in: value), let payloadRange = Range(match.range(at: 3), in: value) else { continue }
            let gap = String(value[cursor..<whole.lowerBound])
            if !(lastWasEncoded && gap.allSatisfy(\.isWhitespace)) { result += gap }
            let payload = String(value[payloadRange])
            let data: Data?
            if value[kindRange].lowercased() == "b" {
                data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            } else {
                // Q encoding: "_" is a space, "=XX" a byte.
                data = quotedPrintableBytes(payload.replacingOccurrences(of: "_", with: " "))
            }
            if let data {
                result += string(from: data, charset: String(value[charsetRange]))
                lastWasEncoded = true
            } else {
                result += String(value[whole])
                lastWasEncoded = false
            }
            cursor = whole.upperBound
        }
        result += String(value[cursor...])
        return result
    }

    private static let encodedWord = try! NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#)  // swiftlint:disable:this force_try

    /// `"Name" <address>`, `Name <address>` or a bare address.
    private static func parseSender(_ header: String) -> (name: String?, address: String?) {
        let decoded = decodeWords(header).trimmingCharacters(in: .whitespacesAndNewlines)
        // Only the first sender of a list.
        if let open = decoded.firstIndex(of: "<"), let close = decoded[open...].firstIndex(of: ">") {
            let address = String(decoded[decoded.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            var name = String(decoded[..<open]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
            name = name.replacingOccurrences(of: "\\\"", with: "\"").trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : name, address.isEmpty ? nil : address)
        }
        let address = decoded.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return (nil, address.isEmpty ? nil : address)
    }

    private static func parseMessageID(_ header: String) -> String? {
        var id = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = id.firstIndex(of: "<"), let close = id[open...].firstIndex(of: ">") {
            id = String(id[id.index(after: open)..<close])
        }
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private static func parseDate(_ header: String) -> Date? {
        // Drop a trailing comment such as "(CEST)".
        var value = header
        if let open = value.firstIndex(of: "(") { value = String(value[..<open]) }
        value = value.trimmingCharacters(in: .whitespaces)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

/// The `message:` link that opens a mail in Apple Mail.
public enum MailLink {
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~@"))

    /// `message://%3C<id>%3E`; the angle brackets of `messageID` are removed and set again, the ID is percent-encoded.
    /// `nil` for an empty ID.
    public static func url(messageID: String) -> URL? {
        var id = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("<") { id.removeFirst() }
        if id.hasSuffix(">") { id.removeLast() }
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://%3C\(encoded)%3E")
    }
}
