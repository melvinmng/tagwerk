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

    /// Returns the sentence announcing `cards`, or `nil` when there is nothing to announce.
    public static func text(for cards: [(title: String, change: String)], language: VoiceLanguage) -> String? {
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
            switch language {
            case .german:
                return "Ich schlage vor: \(title), \(change). Bitte bestätige auf dem Bildschirm."
            case .english:
                return "I suggest: \(title), \(change). Please confirm on the screen."
            }
        default:
            let count = numberText(cards.count, language: language)
            switch language {
            case .german: return "\(capitalizedFirstLetter(count)) Änderungen warten auf deine Bestätigung."
            case .english: return "\(capitalizedFirstLetter(count)) changes are waiting for your confirmation."
            }
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
