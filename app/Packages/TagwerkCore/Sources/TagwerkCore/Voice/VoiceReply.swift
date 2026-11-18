import Foundation

/// A spoken answer to open action cards in the voice mode (issue #120), recognized on the iPhone without
/// asking ChatGPT. Only a whole utterance that is exactly one of the phrases counts: "ja aber um 11" is a
/// correction, not a yes. Filler words like "ok" or "passt" are left out on purpose, they come up too easily
/// in a side conversation.
public enum VoiceReply: Equatable, Sendable {
    case confirm
    /// "Ja, löschen": the only way to confirm a deletion by voice.
    case confirmDelete
    case confirmAll
    case decline
    /// Cancels a running confirmation countdown.
    case stop
    /// Anything else: a new message (a correction).
    case other

    private static let phrases: [String: VoiceReply] = [
        "ja": .confirm, "ja bitte": .confirm, "bestätigen": .confirm,
        "yes": .confirm, "yes please": .confirm, "confirm": .confirm,
        "ja löschen": .confirmDelete, "yes delete": .confirmDelete,
        "alle bestätigen": .confirmAll, "confirm all": .confirmAll,
        "nein": .decline, "verwerfen": .decline, "abbrechen": .decline,
        "no": .decline, "discard": .decline, "cancel": .decline,
        "stopp": .stop, "stop": .stop, "halt": .stop,
    ]

    public init(_ text: String) {
        self = Self.phrases[Self.normalized(text)] ?? .other
    }

    /// Lower case, without punctuation, single spaces.
    static func normalized(_ text: String) -> String {
        let letters = text.lowercased().unicodeScalars.map { CharacterSet.punctuationCharacters.contains($0) ? " " : Character($0) }
        return String(letters).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The action cards that wait for an answer: their call IDs, and how many of them delete something.
public struct OpenCards: Equatable, Sendable {
    public var ids: [String]
    public var deletes: Int

    public init(ids: [String], deletes: Int) {
        self.ids = ids
        self.deletes = deletes
    }

    public static let none = OpenCards(ids: [], deletes: 0)
    public var count: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }
}
