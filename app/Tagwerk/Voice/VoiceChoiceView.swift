import SwiftUI
import TagwerkCore

/// Einstellungen › Sprachen › Spracheingabe und Vorlesen › Stimme Deutsch / Englisch (mockup 5B): the voices of one language by
/// quality, a sample for each, and "Automatisch" as one choice among them. The stored choice is marked from the first frame,
/// before the system list has arrived (#309).
struct VoiceChoiceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    let language: VoiceLanguage
    @Binding var selection: String?
    let model: VoiceSettingsModel

    private var languageName: String { LanguageSettingsText.name(language) }
    private var voices: [SpokenVoice] { model.voices[language] ?? [] }

    var body: some View {
        Form {
            Section {
                choiceRow(title: String(localized: "Automatisch"), detail: automaticDetail, isSelected: selection == nil,
                          voice: model.automaticVoice(for: language), voiceID: nil) { selection = nil }
            }

            if case .pending = model.selection(for: language, selectedID: selection) {
                Section {
                    HStack {
                        checkmark(true)
                        Text("Gewählte Stimme")
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isSelected)
                }
            }

            ForEach(VoiceSection.grouped(voices)) { section in
                Section {
                    ForEach(section.voices) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Text(section.title)
                        .foregroundStyle(.secondaryText)
                }
            }

            Section {
                if case .missing = model.selection(for: language, selectedID: selection) {
                    Text("Die gewählte Stimme ist nicht mehr auf dem iPhone. Tagwerk liest mit der besten geladenen Stimme.")
                }
                Button("Weitere Stimmen laden") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text(footer)
                    .foregroundStyle(.secondaryText)
            }
        }
        .navigationTitle("Stimme \(languageName)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onDisappear { environment.voiceOutput.stop() }
    }

    private func voiceRow(_ voice: SpokenVoice) -> some View {
        choiceRow(title: voice.name, detail: nil, isSelected: selection == voice.id, voice: voice, voiceID: voice.id) {
            selection = voice.id
        }
    }

    /// One row: the choice (checkmark and title, as one button) and the sample as a second button. Two sibling buttons, because a
    /// button inside a button row would also fire the choice.
    private func choiceRow(title: String, detail: String?, isSelected: Bool, voice: SpokenVoice?, voiceID: String?,
                           choose: @escaping () -> Void) -> some View {
        HStack {
            Button(action: choose) {
                HStack {
                    checkmark(isSelected)
                    VStack(alignment: .leading) {
                        Text(verbatim: title)
                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            sampleButton(voice: voice, voiceID: voiceID)
        }
    }

    private func checkmark(_ isSelected: Bool) -> some View {
        Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// The sample of one row: a second tap stops it.
    @ViewBuilder
    private func sampleButton(voice: SpokenVoice?, voiceID: String?) -> some View {
        let isPlaying = environment.voiceOutput.speakingID == VoiceOutputModel.sampleID(voiceID: voiceID)
        Button {
            environment.voiceOutput.speakSample(voiceID: voiceID, language: language)
        } label: {
            Label(isPlaying ? LocalizedStringKey("Stopp") : LocalizedStringKey("Probe"), systemImage: isPlaying ? "stop.fill" : "play.fill")
                .font(.footnote)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPlaying ? String(localized: "Probe beenden") : sampleLabel(voice))
    }

    private func sampleLabel(_ voice: SpokenVoice?) -> String {
        voice.map { String(localized: "Probe \($0.name)") } ?? String(localized: "Probe Automatisch")
    }

    private var automaticDetail: String {
        model.automaticVoice(for: language).map { voice in
            let name = voice.qualityLabel.map { "\(voice.name) (\($0))" } ?? voice.name
            return String(localized: "Nimmt die beste geladene Stimme: \(name)")
        } ?? String(localized: "Nimmt die beste geladene Stimme des iPhones")
    }

    private var footer: String {
        let guide = String(localized: "Stimmen lädst du unter iOS-Einstellungen › Bedienungshilfen › Gesprochene Inhalte › Stimmen.")
        guard model.hasLoadedVoices, let checked = model.voicesCheckedAt else {
            return "\(guide) \(String(localized: "Stimmen werden geladen …"))"
        }
        let time = checked.formatted(date: .omitted, time: .shortened)
        return "\(guide) \(String(localized: "Gefunden: \(voices.count) · zuletzt geprüft \(time)"))"
    }

    private func refresh() async {
        await model.refreshVoices(storedVoiceIDs: environment.settings.storedVoiceIDs)
    }
}
