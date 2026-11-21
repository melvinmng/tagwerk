import Foundation

/// The note texts the assistant read in the running session. Kept in memory only and never stored: it is emptied when
/// the session ends (app quit, switch to another chat, "Verlauf löschen", consent withdrawn). #233 checks against it
/// that a note was read before the assistant changes it.
@MainActor
final class NoteSession {
    /// The text as delivered to the model (possibly cut), by note id.
    private(set) var readTexts: [UUID: String] = [:]
    /// Notes whose delivered text was cut at the length limit.
    private(set) var truncated: Set<UUID> = []

    func remember(_ id: UUID, text: String, truncated isTruncated: Bool) {
        readTexts[id] = text
        if isTruncated { truncated.insert(id) } else { truncated.remove(id) }
    }

    func reset() {
        readTexts = [:]
        truncated = []
    }
}
