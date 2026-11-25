import SwiftUI

/// Settings → Datensicherung → "Was wird gesichert?": three lists instead of long footers on the backup page.
struct BackupCoverageView: View {
    var body: some View {
        List {
            Section {
                ForEach(Self.backedUp, id: \.self) { Text($0) }
            } header: {
                Text("Gesichert")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Alles in einer einzelnen Datei. Beim Wiederherstellen werden die gesicherten Daten ersetzt.")
                    .foregroundStyle(.secondaryText)
            }

            Section {
                ForEach(Self.notBackedUp, id: \.self) { Text($0) }
            } header: {
                Text("Nicht gesichert")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Der Chatverlauf wird nicht gesichert, der Zwischenspeicher lädt Tagwerk neu.")
                    .foregroundStyle(.secondaryText)
            }

            Section {
                ForEach(Self.deviceBound, id: \.self) { Text($0) }
            } header: {
                Text("An dieses Gerät gebunden")
                    .foregroundStyle(.secondaryText)
            } footer: {
                Text("Angaben zu Kalendern, Erinnerungslisten und der Einkaufsliste werden übernommen; fehlen sie auf dem Gerät, verhält sich Tagwerk wie bei einer fehlenden Liste.")
                    .foregroundStyle(.secondaryText)
            }
        }
        .navigationTitle("Was wird gesichert?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var backedUp: [String] {
        [String(localized: "Aufgaben, Zuordnungen zu Tagen und Wiederholungen"),
         String(localized: "Notizen mit ihren Bildern und Dateien"),
         String(localized: "Tagebuch und Bible Study (wenn der Schalter an ist)"),
         String(localized: "Gewohnheiten, Routinen und Reflexionen"),
         String(localized: "Mahlzeiten, Rezepte und Einkaufsliste"),
         String(localized: "Fokus-Sitzungen und Einstellungen")]
    }

    private static var notBackedUp: [String] {
        [String(localized: "Chatverlauf mit dem Assistenten"),
         String(localized: "Zwischenspeicher (GitHub, Vorschläge der Planung)")]
    }

    private static var deviceBound: [String] {
        [String(localized: "Anmeldung bei ChatGPT und GitHub"),
         String(localized: "Zugriff auf Kalender, Erinnerungen und Health"),
         String(localized: "Das Passwort der Sicherung: Tagwerk speichert nur den Schlüssel im Schlüsselbund dieses iPhones, nie das Passwort"),
         String(localized: "Der Sicherungsordner dieses iPhones")]
    }
}
