import Foundation

/// One App Shortcut as the page "Siri & Kurzbefehle" shows it (#188 SI2b).
struct SiriPhrase: Identifiable {
    /// The `shortTitle` of the App Shortcut in `TagwerkShortcuts`; unique.
    let id: String
    /// The first phrase, with "Tagwerk" written out. `scripts/check-strings.py` checks it against `TagwerkIntents.swift`.
    let phrase: LocalizedStringResource
    /// A second phrase that Siri understands as well, shown as "auch: …" (checked like `phrase`).
    let alternative: LocalizedStringResource?
    /// What the shortcut does, in a few words.
    let effect: LocalizedStringResource
    /// The shortcut brings Tagwerk to the front (`supportedModes == .foreground`).
    let opensApp: Bool
}

/// The phrases shown under Einstellungen › Siri & Kurzbefehle, grouped by area. One entry per App Shortcut.
///
/// Keep this list, `TagwerkShortcuts` (TagwerkIntents.swift) and `AppShortcuts.xcstrings` in step; the String Catalog stage of
/// `app/test-all.sh` fails when a shown phrase is not a registered one. `opensApp` follows the intent's `supportedModes`.
enum SiriPhraseCatalog {
    struct Group: Identifiable {
        let id: String
        let title: LocalizedStringResource
        let phrases: [SiriPhrase]
    }

    static let groups: [Group] = [
        Group(id: "capture", title: "Erfassen", phrases: [
            SiriPhrase(id: "Wasser erfassen", phrase: "Wasser in Tagwerk erfassen", alternative: nil,
                       effect: "250 ml, im Hintergrund", opensApp: false),
            SiriPhrase(id: "Mahlzeit erfassen", phrase: "Mahlzeit in Tagwerk erfassen", alternative: nil,
                       effect: "Blatt „Essen“", opensApp: true),
            SiriPhrase(id: "Training erfassen", phrase: "Training in Tagwerk erfassen", alternative: nil,
                       effect: "Blatt „Training“", opensApp: true),
        ]),
        Group(id: "shopping", title: "Einkauf", phrases: [
            SiriPhrase(id: "Artikel auf die Einkaufsliste", phrase: "Füge Milch zur Einkaufsliste in Tagwerk hinzu", alternative: nil,
                       effect: "Artikel im Satz, im Hintergrund", opensApp: false),
            SiriPhrase(id: "Auf die Einkaufsliste", phrase: "Auf die Einkaufsliste in Tagwerk", alternative: nil,
                       effect: "Siri fragt nach den Artikeln", opensApp: false),
            SiriPhrase(id: "Einkaufsliste zeigen", phrase: "Einkaufsliste in Tagwerk zeigen", alternative: nil,
                       effect: "Einkaufsliste", opensApp: true),
        ]),
        Group(id: "day", title: "Tag und Fokus", phrases: [
            SiriPhrase(id: "Heute", phrase: "Was steht heute in Tagwerk an?", alternative: nil,
                       effect: "Termine, Blöcke, Deadlines; nur entsperrt", opensApp: false),
            SiriPhrase(id: "Fokus", phrase: "Fokus starten in Tagwerk", alternative: "Fokus beenden in Tagwerk",
                       effect: "Freier Fokus-Timer, im Hintergrund", opensApp: false),
        ]),
        Group(id: "notes", title: "Notizen und Gewohnheiten", phrases: [
            SiriPhrase(id: "Notiz diktieren", phrase: "Notiz in Tagwerk diktieren", alternative: nil,
                       effect: "Brain Dump mit laufendem Diktat", opensApp: true),
            SiriPhrase(id: "Gewohnheit abhaken", phrase: "Gewohnheit in Tagwerk abhaken", alternative: nil,
                       effect: "Hakt eine Gewohnheit für heute ab", opensApp: false),
        ]),
    ]

    /// The number of App Shortcuts (each has up to two phrases, so more phrases are registered).
    static var shortcutCount: Int { groups.reduce(0) { $0 + $1.phrases.count } }
}
