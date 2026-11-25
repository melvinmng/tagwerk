import SwiftUI
import TagwerkCore

/// Settings of the travel time before events with a place (#168): switch, home address with suggestions, transport and
/// the way home (PL12b, PL15c).
struct TravelSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var address: HomeAddressModel?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var addressFocused: Bool

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Fahrzeit berücksichtigen", isOn: $settings.travelTimeEnabled)
                NavigationLink("Mehr dazu") { TravelInfoView() }
            } footer: {
                Text("Berechnet von Apple Karten. Tagwerk nutzt deinen Standort nicht.")
                    .foregroundStyle(.secondaryText)
            }
            if settings.travelTimeEnabled {
                if let address {
                    addressSection(address)
                }
                Section {
                    Picker("Verkehrsmittel", selection: $settings.travelTransport) {
                        ForEach(TravelTransport.allCases, id: \.self) { transport in
                            Label(TravelText.name(transport), systemImage: TravelText.symbol(transport)).tag(transport)
                        }
                    }
                    Toggle("Rückweg anzeigen", isOn: $settings.travelShowsReturn)
                } footer: {
                    Text("Verkehrsmittel und Start lassen sich je Termin ändern.")
                        .foregroundStyle(.secondaryText)
                }
            }
        }
        .navigationTitle("Fahrzeit")
        .onAppear {
            if address == nil {
                address = HomeAddressModel(settings: environment.settings, suggester: environment.addressSuggester,
                                           lookUp: { try await environment.travelTimes.lookUp(address: $0) },
                                           reload: { await environment.planning.reload() })
            }
        }
        .onDisappear { searchTask?.cancel() }
        .onChange(of: settings.travelTimeEnabled) { _, _ in Task { await environment.planning.reload() } }
        .onChange(of: settings.travelTransportRaw) { _, _ in Task { await environment.planning.reload() } }
        .onChange(of: settings.travelShowsReturn) { _, _ in Task { await environment.planning.reload() } }
    }

    @ViewBuilder
    private func addressSection(_ model: HomeAddressModel) -> some View {
        @Bindable var model = model
        Section {
            HStack {
                TextField("Straße, Ort", text: $model.query)
                    .textContentType(.fullStreetAddress)
                    .submitLabel(.search)
                    .focused($addressFocused)
                    .onChange(of: model.query) { _, _ in
                        // A later keystroke replaces the running search; the model drops the answer of the earlier one.
                        searchTask?.cancel()
                        searchTask = Task { await model.queryChanged() }
                    }
                if !model.query.isEmpty {
                    Button {
                        Task { await model.clear() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adresse löschen")
                }
            }
            ForEach(model.suggestions) { suggestion in
                Button {
                    addressFocused = false
                    Task { await model.choose(suggestion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).foregroundStyle(.primary)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle).font(.subheadline).foregroundStyle(.secondaryText)
                        }
                    }
                }
            }
            statusRow(model)
        } header: {
            Text("Zuhause")
                .foregroundStyle(.secondaryText)
        }
    }

    @ViewBuilder
    private func statusRow(_ model: HomeAddressModel) -> some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) { ProgressView(); Text("Adresse wird gesucht …").foregroundStyle(.secondaryText) }
        case .noSuggestions:
            Text("Keine Vorschläge").foregroundStyle(.secondaryText)
            Button("Adresse trotzdem prüfen") { Task { await model.checkTypedAddress() } }
        case .saved(let description):
            Label(String(localized: "Gesichert: \(description)"), systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.greenText)
        case .failed:
            Label("Adresse nicht gefunden", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(.orangeText)
        }
    }
}
