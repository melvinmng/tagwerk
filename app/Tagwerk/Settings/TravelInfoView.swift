import SwiftUI

/// "Mehr dazu" on the page "Fahrzeit": where the travel time comes from, what goes to Apple and what Tagwerk does when a
/// value is missing (PL12b). The text moved here from the footer of the page, with the sentence on the address search.
struct TravelInfoView: View {
    var body: some View {
        List {
            Section {
                Text("Die Fahrzeit berechnet Apple Karten aus dem Ort des vorherigen Termins oder deiner Heimadresse. Dafür gehen Ort und Adresse an Apple. Tagwerk nutzt deinen Standort nicht. Berechnete Werte bleiben gespeichert und gelten auch ohne Netz. Fehlt ein Wert und gibt es kein Netz, schätzt Tagwerk die Fahrzeit vorläufig: mit dem letzten bekannten Wert zum selben Ziel, sonst mit 30 Minuten. Ohne Ort gibt es keine Fahrzeit. Im Termin lässt sie sich auch von Hand festlegen.")
            }
            Section {
                Text("Beim Tippen der Adresse gehen deine Eingaben an Apple Karten.")
            }
            Section {
                Text("Der Rückweg gilt nach dem letzten Termin des Tages und vor Pausen von mehr als drei Stunden. Er zählt wie die Hinfahrt als belegte Zeit.")
            }
        }
        .navigationTitle("Fahrzeit")
        .navigationBarTitleDisplayMode(.inline)
    }
}
