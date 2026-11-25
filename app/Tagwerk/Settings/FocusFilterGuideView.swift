import SwiftUI

/// Einstellungen › Benachrichtigungen › Ruhezeiten › Bei iOS-Fokus zurückhalten (plan g1, RH1b): how to add the Focus
/// filter of Tagwerk and the rule it follows. iOS offers no public link into the Focus settings, so the page only names
/// the way.
struct FocusFilterGuideView: View {
    var body: some View {
        Form {
            Section {
                step(1, "Öffne die iOS-Einstellungen und tippe auf „Fokus“.")
                step(2, "Wähle einen Fokus, zum Beispiel „Arbeiten“.")
                step(3, "Tippe unter „Fokusfilter“ auf „Filter hinzufügen“ und wähle „Tagwerk“.")
                step(4, "Schalte „Aufgaben und Deadlines zurückhalten“ ein.")
            } header: {
                Text("So richtest du ihn ein")
                    .foregroundStyle(.secondaryText)
            }
            Section {
                Text("Solange der Fokus läuft, hält Tagwerk Mitteilungen zu Aufgaben und Deadline-Terminen zurück. Sie kommen, sobald der Fokus endet. Meldet iOS das Ende nicht, kommen sie spätestens nach 4 Stunden. Fällt dieser Zeitpunkt in die Ruhezeit, kommen sie an deren Ende. Nichts entfällt.")
            } header: {
                Text("Was passiert")
                    .foregroundStyle(.secondaryText)
            }
        }
        .navigationTitle("Fokus-Filter")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(minWidth: 24)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
