/// Spoken announcements for pending action cards.
public enum ActionAnnouncement {
    /// Largest count that is spoken as a word; larger counts are spoken as digits.
    private static let largestNumberWord = 12

    private static let germanNumberWords = [
        "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"
    ]
    private static let englishNumberWords = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"
    ]

    /// Returns the sentence announcing `cards`, or `nil` when there is nothing to announce. `byVoice`: the voice
    /// mode, where the user answers by speaking (issue #120); `deletes` counts the cards that delete something.
    public static func text(for cards: [(title: String, change: String)], language: VoiceLanguage,
                            byVoice: Bool = false, deletes: Int = 0) -> String? {
        switch cards.count {
        case 0:
            return nil
        case 1:
            let card = cards[0]
            let title = SpokenText.prepare(card.title, language: language)
            let change = SpokenText.prepare(
                card.change.replacingOccurrences(of: " · ", with: ", "),
                language: language
            )
            switch (language, byVoice, deletes > 0) {
            case (.german, false, _):
                return "Ich schlage vor: \(title), \(change). Bitte bestätige auf dem Bildschirm."
            case (.english, false, _):
                return "I suggest: \(title), \(change). Please confirm on the screen."
            case (.german, true, false):
                return "Ich schlage vor: \(title), \(change). Sag ja oder nein, oder was anders sein soll."
            case (.english, true, false):
                return "I suggest: \(title), \(change). Say yes or no, or what should be different."
            case (.german, true, true):
                return "Ich schlage vor: \(title), \(change). Zum Löschen sag: Ja, löschen. Oder nein."
            case (.english, true, true):
                return "I suggest: \(title), \(change). To delete, say: yes, delete. Or no."
            }
        default:
            let count = numberText(cards.count, language: language)
            if byVoice {
                switch language {
                case .german: return "\(capitalizedFirstLetter(count)) Änderungen warten. Sag alle bestätigen, oder tippe auf eine Karte."
                case .english: return "\(capitalizedFirstLetter(count)) changes are waiting. Say confirm all, or tap a card."
                }
            }
            switch language {
            case .german: return "\(capitalizedFirstLetter(count)) Änderungen warten auf deine Bestätigung."
            case .english: return "\(capitalizedFirstLetter(count)) changes are waiting for your confirmation."
            }
        }
    }

    /// Short answers of the voice mode to a spoken reply (issue #120).
    public enum Prompt: Equatable, Sendable {
        /// "Ja" with several cards open.
        case severalCards(Int)
        /// "Ja" for a deletion.
        case sayDelete
        /// "Alle bestätigen" while a deletion is among the cards.
        case deletesNeedTap
        /// "Alle bestätigen" while a card assigns an issue to other people or to no one.
        case guardedNeedTap
        /// "Alle bestätigen" while a card creates or revises a note.
        case notesNeedSingle
        /// The confirmation countdown was stopped.
        case cancelled
    }

    public static func prompt(_ prompt: Prompt, language: VoiceLanguage) -> String {
        switch (prompt, language) {
        case (.severalCards(let count), .german):
            "Es sind \(numberText(count, language: language)) Vorschläge offen. Sag alle bestätigen, oder tippe auf eine Karte."
        case (.severalCards(let count), .english):
            "There are \(numberText(count, language: language)) suggestions open. Say confirm all, or tap a card."
        case (.sayDelete, .german): "Zum Löschen sag: Ja, löschen."
        case (.sayDelete, .english): "To delete, say: yes, delete."
        case (.deletesNeedTap, .german): "Löschungen bitte einzeln bestätigen."
        case (.deletesNeedTap, .english): "Please confirm deletions one by one."
        case (.guardedNeedTap, .german): "Zuweisungen bitte einzeln bestätigen."
        case (.guardedNeedTap, .english): "Please confirm assignments one by one."
        case (.notesNeedSingle, .german): "Notiz-Änderungen bitte einzeln bestätigen."
        case (.notesNeedSingle, .english): "Please confirm changes to notes one by one."
        case (.cancelled, .german): "Abgebrochen."
        case (.cancelled, .english): "Cancelled."
        }
    }

    /// Short confirmation spoken after the user confirmed the cards.
    public static func executed(_ language: VoiceLanguage) -> String {
        switch language {
        case .german: "Ausgeführt."
        case .english: "Done."
        }
    }

    private static func numberText(_ count: Int, language: VoiceLanguage) -> String {
        guard (2...largestNumberWord).contains(count) else { return String(count) }
        switch language {
        case .german: return germanNumberWords[count - 2]
        case .english: return englishNumberWords[count - 2]
        }
    }

    private static func capitalizedFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
