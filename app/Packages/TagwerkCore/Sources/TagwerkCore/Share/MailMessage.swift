import Foundation

/// The parts of a mail Tagwerk keeps: the headers it needs and the readable text. Attachments and recipients are never
/// read, so they cannot end up in the inbox or in a request.
public struct MailMessage: Sendable, Hashable, Codable {
    public var subject: String
    public var senderName: String?
    public var senderAddress: String?
    public var date: Date?
    /// The `Message-ID` header without the angle brackets.
    public var messageID: String?
    public var bodyText: String

    public init(subject: String, senderName: String? = nil, senderAddress: String? = nil, date: Date? = nil,
                messageID: String? = nil, bodyText: String) {
        self.subject = subject
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.date = date
        self.messageID = messageID
        self.bodyText = bodyText
    }
}
