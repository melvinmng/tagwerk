import AppIntents
import SwiftUI

/// Einstellungen › Siri & Kurzbefehle (#188 SI1b, SI2b): the link to the Shortcuts app first, then the phrases in four groups.
/// No `SiriTipView` here; the page is the list itself. The tip cards sit where the action happens (shopping list, drink buttons).
struct SiriShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                // Opens the Shortcuts app on the shortcuts of this app; it only renders when the shortcuts are registered.
                ShortcutsLink()
            } footer: {
                Text("Alle Sätze stehen dort bereit, auch für Aktionstaste und Home-Bildschirm.")
            }

            ForEach(SiriPhraseCatalog.groups) { group in
                Section {
                    ForEach(group.phrases) { phrase in
                        SiriPhraseRow(phrase: phrase)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if group.id == SiriPhraseCatalog.groups.last?.id {
                        Text("Erkennt Siri einen Satz nicht, prüfe in der App „Kurzbefehle“, ob dort die Tagwerk-Kurzbefehle stehen, und probiere den Satz als Text über „Tippen für Siri“.")
                    }
                }
            }
        }
        .navigationTitle("Siri & Kurzbefehle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One phrase with its effect; read by VoiceOver as one element.
private struct SiriPhraseRow: View {
    let phrase: SiriPhrase

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("„\(String(localized: phrase.phrase))“")
            if let alternative = phrase.alternative {
                Text("auch: „\(String(localized: alternative))“")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(phrase.effect)
                if phrase.opensApp {
                    Label("öffnet Tagwerk", systemImage: "arrow.up.forward.app")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
