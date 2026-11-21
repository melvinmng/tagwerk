import SwiftUI
import TagwerkCore

/// Creates the dictation model of one message field from the app's settings and recognizer.
@MainActor
enum VoiceInputFactory {
    static func make(_ environment: AppEnvironment, place: DictationPlace) -> VoiceInputModel {
        let settings = environment.settings
        let model = VoiceInputModel(language: settings.dictationLanguage(at: place), place: place,
                                    makeRecognizer: environment.makeRecognizer,
                                    isExplained: { settings.voiceExplained },
                                    markExplained: { settings.voiceExplained = true })
        model.onRecordingStarts = { environment.voiceOutput.stop() }
        model.onLanguageSwitched = { settings.rememberDictationLanguage($0, at: place) }
        return model
    }
}

/// Microphone inside a message field (mockup SP1a): about 30 pt visible, 44 pt to tap.
struct VoiceMicrophoneButton: View {
    let voice: VoiceInputModel
    let isEnabled: Bool
    let language: VoiceLanguage

    var body: some View {
        Button {
            voice.setLanguage(language)
            voice.tapMicrophone()
        } label: {
            Image(systemName: isEnabled ? "mic" : "mic.slash")
                .font(.body)
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Sprechen")
    }
}

/// The recording bar that replaces the field while dictating (SP1a full, SP6b compact).
struct VoiceRecordingBar: View {
    let voice: VoiceInputModel
    /// The compact form of the suggestion sheet: no "Fertig", a tap on the text ends the recording.
    var compact = false
    var canSend = true
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !compact {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Hört zu · auf dem iPhone").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    LanguageChip(language: voice.language, style: .named) { voice.switchLanguage() }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.clock(voice.elapsed())).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    transcript
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { if compact { voice.finish() } }
                    LevelMeter(level: voice.level)
                }
                if compact { LanguageChip(language: voice.language, style: .short) { voice.switchLanguage() } }
                Button { voice.cancel() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered).clipShape(Circle())
                .accessibilityLabel("Aufnahme verwerfen")
                if !compact {
                    Button { voice.finish() } label: {
                        Label("Fertig", systemImage: "stop.fill").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Aufnahme beenden")
                }
                Button { voice.send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .disabled(!canSend)
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.red.opacity(0.8), lineWidth: 1.5))
    }

    private var transcript: some View {
        let machine = voice.machine
        let typed = TranscriptAccumulator.join(machine.draftBefore, machine.finalText)
        let placeholder = typed.isEmpty && machine.volatileText.isEmpty
        return Group {
            if placeholder {
                Text(compact ? "Sprich jetzt …" : "Sprich jetzt, nichts wird gesendet, bevor du ↑ tippst.")
                    .foregroundStyle(.secondary)
            } else {
                Text(typed) + Text(machine.volatileText.isEmpty ? "" : (typed.isEmpty ? "" : " ") + machine.volatileText)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(compact ? 2 : 5)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// The switch of the dictation language (mockups SP3b, SP5b): the language's name, or its short form where the row is narrow,
/// with the switch symbol; 44 pt to tap. A tap changes to the other language.
struct LanguageChip: View {
    enum Style { case named, short }

    let language: VoiceLanguage
    var style: Style = .named
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(style == .named ? LanguageSettingsText.name(language) : language.shortName)
                Image(systemName: "arrow.left.arrow.right")
            }
            .font(style == .named ? .footnote.weight(.semibold) : .caption2.weight(.semibold))
            .padding(.horizontal, style == .named ? 10 : 6).padding(.vertical, 4)
            .background(.secondary.opacity(0.2), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Names the language and the one a tap switches to; both texts are German source keys.
    private var label: LocalizedStringKey {
        language == .german ? "Sprache Deutsch, auf Englisch wechseln" : "Sprache Englisch, auf Deutsch wechseln"
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(.secondary.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule().fill(.red.opacity(0.7)).frame(width: proxy.size.width * CGFloat(level))
                }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

/// Explanation before the first recording and short notices (mockups SP8a, b, e).
struct VoiceNoticeRow: View {
    let voice: VoiceInputModel

    var body: some View {
        switch voice.phase {
        case .explaining:
            VStack(alignment: .leading, spacing: 8) {
                Label("Mit Tagwerk sprechen", systemImage: "mic").font(.subheadline.weight(.semibold))
                Text("Tagwerk wandelt deine Sprache auf dem iPhone in Text um. Der Ton verlässt das Gerät nicht. Gesendet wird erst, wenn du ↑ tippst.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Dafür fragt iOS gleich nach dem Mikrofon.").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Nicht jetzt") { voice.dismissExplanation() }.buttonStyle(.bordered)
                    Spacer()
                    Button("Weiter") { voice.continueAfterExplanation() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        case .notice(let notice):
            HStack(alignment: .firstTextBaseline) {
                Label(Self.text(notice), systemImage: Self.symbol(notice)).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if notice == .permissionDenied {
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.footnote)
                }
            }
        default:
            EmptyView()
        }
    }

    static func text(_ notice: DictationMachine.Notice) -> String {
        switch notice {
        case .nothingHeard: String(localized: "Nichts verstanden. Es kam kein Text an. Sprich näher am iPhone oder tippe.")
        case .interrupted: String(localized: "Aufnahme unterbrochen. Der Text bis dahin steht im Feld.")
        case .unsupported: String(localized: "Spracherkennung ist auf diesem iPhone nicht verfügbar. Tippen geht weiter.")
        case .permissionDenied: String(localized: "Mikrofon nicht erlaubt. Tippen geht weiter.")
        case .assetUnavailable: String(localized: "Sprachpaket fehlt. Es lädt, sobald du online bist.")
        case .failed: String(localized: "Die Aufnahme ist fehlgeschlagen. Tippen geht weiter.")
        }
    }

    static func symbol(_ notice: DictationMachine.Notice) -> String {
        switch notice {
        case .permissionDenied: "mic.slash"
        case .assetUnavailable: "arrow.down.circle"
        default: "exclamationmark.bubble"
        }
    }
}

/// The capsule under an answer (SP3a): "Vorlesen", while playing "Liest vor · Stopp".
struct ReadAloudButton: View {
    @Environment(AppEnvironment.self) private var environment
    let id: String
    let text: String

    var body: some View {
        // The voice mode reads on its own; a second reading would be heard by its microphone (stage 2 review 2).
        if !environment.voiceMode.isRunning { button }
    }

    private var button: some View {
        let output = environment.voiceOutput
        let playing = output.speakingID == id
        return Button {
            output.toggle(id: id, text: text, fallback: environment.settings.contentLanguages.readAloudFallback())
        } label: {
            Label(playing ? "Liest vor · Stopp" : "Vorlesen", systemImage: playing ? "stop.fill" : "speaker.wave.2")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(playing ? Color.accentColor : .secondary)
        .accessibilityLabel(playing ? "Vorlesen stoppen" : "Vorlesen")
    }
}

/// An answer drawn from its Markdown, with the sentence being read highlighted (SP3a, #225).
struct SpokenAnswerText: View {
    @Environment(AppEnvironment.self) private var environment
    let id: String
    let text: String

    var body: some View {
        let output = environment.voiceOutput
        let sentence = output.speakingID == id && output.sentences.indices.contains(output.currentSentence)
            ? output.sentences[output.currentSentence] : nil
        ChatMarkdownView(text: text, spokenSentence: sentence)
    }

    /// The spoken sentence is prepared text; its first words locate it in the shown text.
    static func range(of sentence: String, in text: String) -> Range<String.Index>? {
        let words = sentence.split(separator: " ").prefix(3).joined(separator: " ")
        guard !words.isEmpty, let start = text.range(of: words)?.lowerBound else { return nil }
        let rest = text[start...]
        let end = rest.firstIndex(where: { ".!?".contains($0) }).map { text.index(after: $0) } ?? text.endIndex
        return start..<end
    }

    /// `text` with the part that `sentence` points to marked; unchanged when the sentence is not in it (for example because
    /// it belongs to another block, or its wording was changed for speaking).
    static func highlighted(_ text: AttributedString, sentence: String) -> AttributedString {
        let shown = String(text.characters)
        guard let range = range(of: sentence, in: shown) else { return text }
        var attributed = text
        if let lower = AttributedString.Index(range.lowerBound, within: attributed),
           let upper = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[lower..<upper].backgroundColor = .accentColor.opacity(0.2)
        }
        return attributed
    }
}

/// "Kopieren" under an answer: the answer as plain text, without Markdown symbols. Selecting text works only inside one
/// block of a rendered answer, so the whole answer needs its own way to the pasteboard.
struct CopyAnswerButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = MarkdownText.plainText(text)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
