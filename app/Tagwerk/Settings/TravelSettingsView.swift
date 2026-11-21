import SwiftUI
import TagwerkCore

/// Settings of the travel time before events with a place (#168): switch, home address and transport.
struct TravelSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var addressText = ""
    @State private var status: AddressStatus = .idle
    @FocusState private var addressFocused: Bool

    private enum AddressStatus: Equatable {
        case idle, checking, found(String), notFound
    }

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Fahrzeit berücksichtigen", isOn: $settings.travelTimeEnabled)
            } footer: {
                Text("Die Fahrzeit berechnet Apple Karten aus dem Ort des vorherigen Termins oder deiner Heimadresse. Dafür gehen Ort und Adresse an Apple. Tagwerk nutzt deinen Standort nicht. Berechnete Werte bleiben gespeichert und gelten auch ohne Netz. Fehlt ein Wert und gibt es kein Netz, schätzt Tagwerk die Fahrzeit vorläufig: mit dem letzten bekannten Wert zum selben Ziel, sonst mit 30 Minuten. Ohne Ort gibt es keine Fahrzeit. Im Termin lässt sie sich auch von Hand festlegen.")
            }
            if settings.travelTimeEnabled {
                Section {
                    TextField("Straße, Ort", text: $addressText)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.done)
                        .focused($addressFocused)
                        .onSubmit { Task { await checkAddress() } }
                    statusRow
                } header: {
                    Text("Heimadresse")
                }
                Section {
                    Picker("Verkehrsmittel", selection: $settings.travelTransport) {
                        ForEach(TravelTransport.allCases, id: \.self) { transport in
                            Label(TravelText.name(transport), systemImage: TravelText.symbol(transport)).tag(transport)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fahrzeit")
        .onAppear {
            addressText = settings.homeAddress ?? ""
            if settings.homePlace != nil, settings.homeLatitude != nil { status = .found(addressText) }
        }
        .onDisappear { if addressFocused { Task { await checkAddress() } } }
        .onChange(of: settings.travelTimeEnabled) { _, _ in Task { await environment.planning.reload() } }
        .onChange(of: settings.travelTransportRaw) { _, _ in Task { await environment.planning.reload() } }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) { ProgressView(); Text("Adresse wird geprüft …").foregroundStyle(.secondaryText) }
        case .found(let description):
            Label(String(localized: "Gefunden: \(description)"), systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.greenText)
        case .notFound:
            Label("Adresse nicht gefunden", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(.orangeText)
        }
    }

    /// Checks the typed address with Apple Maps and stores it with its coordinates; an empty field removes it.
    /// An address that is not found is not stored.
    private func checkAddress() async {
        let settings = environment.settings
        let text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != (settings.homeAddress ?? "") || settings.homeLatitude == nil else { return }
        guard !text.isEmpty else {
            settings.homeAddress = nil
            settings.homeLatitude = nil
            settings.homeLongitude = nil
            status = .idle
            await environment.planning.reload()
            return
        }
        status = .checking
        do {
            let found = try await environment.travelTimes.lookUp(address: text)
            settings.homeAddress = text
            settings.homeLatitude = found.latitude
            settings.homeLongitude = found.longitude
            status = .found(found.description)
            await environment.planning.reload()
        } catch {
            status = .notFound
        }
    }
}
