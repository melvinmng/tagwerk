import AVFoundation
import Speech
import SwiftUI
import TagwerkCore

/// State of one language pack on this iPhone.
enum LanguagePackState: Equatable {
    case installed, available, downloading, unsupported

    var label: String {
        switch self {
        case .installed: String(localized: "Geladen · auf dem iPhone")
        case .available: String(localized: "Wird beim ersten Sprechen geladen")
        case .downloading: String(localized: "Wird geladen …")
        case .unsupported: String(localized: "Nicht unterstützt")
        }
    }
}

enum VoiceAvailability {
    static func packState(_ language: VoiceLanguage) async -> LanguagePackState {
        guard let module = await AppleSpeechRecognizer.module(.dictation, language: language) else { return .unsupported }
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .installed
        case .downloading: return .downloading
        case .supported: return .available
        default: return .unsupported
        }
    }

    /// The language used for recognition and as the voice chat language: the setting, or the app language when it says "auto".
    static func recognitionLanguage(setting: String, locale: Locale = .current) -> VoiceLanguage {
        VoiceChatLanguage.resolve(setting: setting, locale: locale)
    }

    /// "Mikrofon an, Vorlesen nie" for the row in "KI".
    static func summary(inputEnabled: Bool, readAloud: String) -> String {
        let policy = ReadAloudPolicy(rawValue: readAloud) ?? .never
        let readAloud = policy.title.lowercased()
        return inputEnabled ? String(localized: "Mikrofon an, Vorlesen \(readAloud)") : String(localized: "Mikrofon aus, Vorlesen \(readAloud)")
    }
}

/// Einstellungen › Sprachen › Spracheingabe und Vorlesen (mockup SP7a), with the voice mode section (Task 12). The content
/// languages themselves are on `LanguageSettingsView`.
struct VoiceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = VoiceSettingsModel()

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Mikrofon in Gesprächen", isOn: $settings.voiceInputEnabled)
                microphoneRow
                ForEach(VoiceLanguage.allCases, id: \.self) { language in
                    LabeledContent("Sprachpaket \(LanguageSettingsText.name(language))", value: model.packs[language]?.label ?? "…")
                }
            } header: {
                Text("Spracheingabe")
            } footer: {
                Text("Tagwerk wandelt Sprache auf dem iPhone in Text um. Der Ton verlässt das Gerät nicht. An ChatGPT geht nur der Text, den du sendest.")
            }

            Section {
                Picker("Antworten vorlesen", selection: $settings.voiceReadAloud) {
                    ForEach(ReadAloudPolicy.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Änderungen ansagen", isOn: $settings.voiceAnnounceActions)
                voiceLink(.german, selection: $settings.voiceGermanVoiceID)
                voiceLink(.english, selection: $settings.voiceEnglishVoiceID)
                VStack(alignment: .leading) {
                    Text("Tempo")
                    Slider(value: $settings.voiceRate, in: 0.3...0.65) {
                        Text("Tempo")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
                Button("Probe hören") {
                    let german = settings.contentLanguages.dictationLanguage(at: nil) == .german
                    environment.voiceOutput.speak(
                        id: "sample",
                        text: german ? "So klingt Tagwerk, wenn es dir eine Antwort vorliest."
                            : "This is how Tagwerk sounds when it reads an answer to you.",
                        explicit: true, fallback: german ? .german : .english)
                }
            } header: {
                Text("Vorlesen")
            } footer: {
                Text("Vorgelesen wird mit den Stimmen dieses iPhones. Die Stimme wählst du je Sprache auf einer eigenen Seite, mit Hörprobe. Bei stummem iPhone liest Tagwerk nur vor, wenn du „Vorlesen“ antippst.")
                    .foregroundStyle(.secondaryText)
            }

            Section {
                Picker("Senden nach Pause", selection: $settings.voiceModeSendDelay) {
                    ForEach([1.0, 2.0, 3.0], id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                Picker("Pausiert nach Stille", selection: $settings.voiceModeSilenceLimit) {
                    ForEach([15.0, 30.0, 60.0], id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
            } header: {
                Text("Sprechmodus")
            } footer: {
                Text("Im Chat startet der Knopf rechts neben dem leeren Feld den Sprechmodus. Tagwerk sendet nach der Pause, liest die Antwort vor und hört danach wieder zu. Änderungen führt es erst aus, wenn du sie bestätigst. „Änderungen ansagen“ gilt auch hier.")
            }
        }
        .navigationTitle("Spracheingabe und Vorlesen")
        .task { await refresh() }
        // Voices are downloaded in the iOS settings: the list is read again when the user comes back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onDisappear { environment.voiceOutput.stop() }
    }

    private func refresh() async {
        await model.refresh(storedVoiceIDs: environment.settings.storedVoiceIDs)
    }

    @ViewBuilder
    private var microphoneRow: some View {
        switch model.microphone {
        case .granted:
            LabeledContent("Mikrofon", value: "Erlaubt")
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                LabeledContent("Mikrofon", value: "Nicht erlaubt · Einstellungen öffnen")
            }
        default:
            LabeledContent("Mikrofon", value: "Wird beim ersten Sprechen gefragt")
        }
    }

    private func voiceLink(_ language: VoiceLanguage, selection: Binding<String?>) -> some View {
        NavigationLink {
            VoiceChoiceView(language: language, selection: selection, model: model)
        } label: {
            LabeledContent("Stimme \(LanguageSettingsText.name(language))", value: model.selectionTitle(for: language, selectedID: selection.wrappedValue))
        }
    }
}

extension VoiceSettingsModel {
    /// The value shown next to the row "Stimme …": the voice, "Automatisch", or, until the list is there, a neutral name for the stored one.
    func selectionTitle(for language: VoiceLanguage, selectedID: String?) -> String {
        switch selection(for: language, selectedID: selectedID) {
        case .automatic: String(localized: "Automatisch")
        case .pending: String(localized: "Gewählte Stimme")
        case .voice(let voice): voice.qualityLabel.map { "\(voice.name) (\($0))" } ?? voice.name
        case .missing: String(localized: "Nicht mehr geladen")
        }
    }
}

extension AppSettings {
    /// The voices chosen in the settings, one per language; "Automatisch" has no entry.
    var storedVoiceIDs: [VoiceLanguage: String] {
        var stored: [VoiceLanguage: String] = [:]
        if let voiceGermanVoiceID { stored[.german] = voiceGermanVoiceID }
        if let voiceEnglishVoiceID { stored[.english] = voiceEnglishVoiceID }
        return stored
    }
}
