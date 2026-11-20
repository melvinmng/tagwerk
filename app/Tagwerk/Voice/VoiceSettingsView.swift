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

/// Einstellungen › KI › Sprache (mockup SP7a), with the voice mode section (Task 12).
struct VoiceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var packs: [VoiceLanguage: LanguagePackState] = [:]
    @State private var voices: [VoiceLanguage: [SpokenVoice]] = [:]

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Mikrofon in Gesprächen", isOn: $settings.voiceInputEnabled)
                microphoneRow
                ForEach(VoiceLanguage.allCases, id: \.self) { language in
                    LabeledContent("Sprachpaket \(Self.name(language))", value: packs[language]?.label ?? "…")
                }
            } header: {
                Text("Spracheingabe")
            } footer: {
                Text("Tagwerk wandelt Sprache auf dem iPhone in Text um. Der Ton verlässt das Gerät nicht. An ChatGPT geht nur der Text, den du sendest.")
            }

            Section {
                // Same stored value as the former "Erkennung in" ("auto", "de-DE", "en-US"), so nothing was migrated.
                Picker("Sprache im Sprachchat", selection: $settings.voiceRecognitionLanguage) {
                    Text("Wie die App").tag(VoiceChatLanguage.automatic)
                    ForEach(VoiceChatLanguage.choices, id: \.self) { Text(Self.name($0)).tag($0.rawValue) }
                }
            } header: {
                Text("Sprachchat")
            } footer: {
                Text("Die Sprache gilt für die Spracherkennung (auch beim Diktieren in Notizen, Einkauf und Mahlzeiten), für die Antwort von ChatGPT im Sprechmodus und für die Stimme beim Vorlesen. „Wie die App“ nimmt die Sprache der App; ChatGPT antwortet dann in der Sprache, in der du sprichst. Im getippten Chat antwortet ChatGPT weiter in der Sprache, in der du schreibst.")
            }

            Section {
                Picker("Sprache für Rezepte", selection: $settings.recipeLanguage) {
                    Text("Wie die App").tag(RecipeLanguage.automatic)
                    ForEach(RecipeLanguage.choices, id: \.self) { Text(Self.name($0)).tag($0.rawValue) }
                }
            } header: {
                Text("Rezepte")
            } footer: {
                Text("Titel, Zutaten und Zubereitung eines Rezepts schreibt ChatGPT in dieser Sprache und übersetzt, wenn das Rezept eine andere hat. Die Artikel auf der Einkaufsliste folgen ihr. „Wie die App“ nimmt die Sprache der App.")
            }

            Section {
                Picker("Antworten vorlesen", selection: $settings.voiceReadAloud) {
                    ForEach(ReadAloudPolicy.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Änderungen ansagen", isOn: $settings.voiceAnnounceActions)
                voicePicker(.german, selection: $settings.voiceGermanVoiceID)
                voicePicker(.english, selection: $settings.voiceEnglishVoiceID)
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
                    let german = VoiceAvailability.recognitionLanguage(setting: settings.voiceRecognitionLanguage) == .german
                    environment.voiceOutput.speak(
                        id: "sample",
                        text: german ? "So klingt Tagwerk, wenn es dir eine Antwort vorliest."
                            : "This is how Tagwerk sounds when it reads an answer to you.",
                        explicit: true, fallback: german ? .german : .english)
                }
            } header: {
                Text("Vorlesen")
            } footer: {
                Text("Vorgelesen wird mit den Stimmen dieses iPhones. Bessere Stimmen lädst du unter iOS-Einstellungen › Bedienungshilfen › Gesprochene Inhalte › Stimmen. Bei stummem iPhone liest Tagwerk nur vor, wenn du „Vorlesen“ antippst.")
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
        .navigationTitle("Sprache")
        .task { await refresh() }
        .onDisappear { environment.voiceOutput.stop() }
    }

    @ViewBuilder
    private var microphoneRow: some View {
        switch microphone {
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

    private func voicePicker(_ language: VoiceLanguage, selection: Binding<String?>) -> some View {
        Picker("Stimme \(Self.name(language))", selection: selection) {
            Text("Automatisch").tag(String?.none)
            ForEach(voices[language] ?? []) { voice in
                Text(voice.qualityLabel.map { "\(voice.name) (\($0))" } ?? voice.name).tag(Optional(voice.id))
            }
        }
    }

    private func refresh() async {
        microphone = AVAudioApplication.shared.recordPermission
        let speaker = SystemSpeaker()
        for language in VoiceLanguage.allCases {
            packs[language] = await VoiceAvailability.packState(language)
            voices[language] = speaker.voices(for: language)
        }
    }

    static func name(_ language: VoiceLanguage) -> String { language == .german ? String(localized: "Deutsch") : String(localized: "English") }
}
