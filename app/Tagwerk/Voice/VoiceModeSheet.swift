import AIKit
import SwiftUI
import TagwerkCore

/// The voice mode inside the chat sheet (mockup SP5a): state line, the last exchange, an open action card,
/// and "Pause"/"Unterbrechen", "Tippen", "Verlauf". The sheet sits at half height over the calendar.
struct VoiceModePanel: View {
    @Environment(AppEnvironment.self) private var environment
    let assistant: AssistantModel
    let contextText: String
    /// At full height the chat above shows the history; the panel then only shows state and controls.
    var showsExchange = true
    /// "Verlauf": pull the sheet to full height.
    let onShowHistory: () -> Void

    private var mode: VoiceModeController { environment.voiceMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusLine
            if showsExchange {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        lastExchange
                        pendingCards
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            controls
        }
        .padding()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Label("Sprechmodus", systemImage: "sparkles").font(.headline)
            Spacer()
            Button("Beenden") { mode.end() }.buttonStyle(.bordered)
        }
        .overlay(alignment: .bottomLeading) {
            Text(contextText).font(.caption).foregroundStyle(.secondary).offset(y: 18)
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch mode.phase {
        case .starting:
            status("Startet …", symbol: "mic", tint: .secondary)
        case .listening:
            VStack(alignment: .leading, spacing: 6) {
                status(mode.machine.openCards.isEmpty ? "Hört zu … · auf dem iPhone" : "Hört zu … · sag ja, nein oder was anders sein soll",
                       symbol: "waveform", tint: .red)
                heardText
                LevelMeter(level: mode.level)
            }
        case .countdown:
            VStack(alignment: .leading, spacing: 6) {
                heardText
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    HStack {
                        Label("Sendet in \(mode.remaining()) s", systemImage: "timer").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("Nicht senden") { mode.doNotSend() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        case .finalizing:
            VStack(alignment: .leading, spacing: 6) {
                heardText
                HStack {
                    Label("Sendet …", systemImage: "arrow.up.circle").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Nicht senden") { mode.doNotSend() }.buttonStyle(.borderedProminent)
                }
            }
        case .sending:
            status("Sendet an ChatGPT …", symbol: "arrow.up.circle", tint: .secondary)
        case .speaking:
            status("ChatGPT spricht … · Mikrofon aus", symbol: "speaker.wave.2", tint: .accentColor)
        case .tone:
            status("Gleich hört Tagwerk wieder zu", symbol: "bell", tint: .secondary)
        case .confirming:
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                HStack {
                    Label("Wird in \(mode.remaining()) s ausgeführt", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.purple)
                    Spacer()
                    Button("Abbrechen") { mode.cancelConfirmation() }.buttonStyle(.borderedProminent)
                }
            }
        case .paused(let reason):
            status(Self.text(reason), symbol: "pause.circle", tint: .orange)
        case .idle, .ended:
            EmptyView()
        }
    }

    private var heardText: some View {
        let text = mode.machine.text
        return Text(text.isEmpty ? "Sprich jetzt." : text)
            .font(.title3)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .lineLimit(4)
    }

    private func status(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
    }

    /// The last user message and answer, like the mockup's "Du" and "ChatGPT" rows.
    @ViewBuilder
    private var lastExchange: some View {
        let messages = assistant.conversation?.messages ?? []
        if let user = messages.last(where: { if case .user = $0.content { true } else { false } }),
           case .user(let text) = user.content {
            VStack(alignment: .leading, spacing: 2) {
                Text("Du").font(.caption).foregroundStyle(.secondary)
                Text(text)
            }
            let answers = messages.filter { $0.id > user.id }
            ForEach(answers) { message in
                if case .assistant(let answer) = message.content {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ChatGPT").font(.caption).foregroundStyle(.secondary)
                        SpokenAnswerText(id: "message-\(message.id)", text: answer)
                    }
                }
            }
        }
        if let streaming = assistant.conversation?.streamingText, !streaming.isEmpty {
            Text(streaming).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pendingCards: some View {
        ForEach(assistant.conversation?.pendingActions ?? [], id: \.id) { call in
            ActionCardView(card: assistant.describe(call), status: .pending, time: nil,
                           onConfirm: { Task { await assistant.confirm(call) } },
                           onDecline: { Task { await assistant.decline(call) } })
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            primaryControl
            Spacer()
            Button { mode.typeInstead() } label: { Label("Tippen", systemImage: "keyboard") }
                .buttonStyle(.bordered)
            Button(action: onShowHistory) { Label("Verlauf", systemImage: "text.bubble") }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch mode.phase {
        case .speaking:
            Button { mode.interrupt() } label: { Label("Unterbrechen", systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent)
        case .paused:
            Button { mode.resume() } label: { Label("Weiter", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
        case .starting, .listening, .countdown:
            Button { mode.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }

    static func text(_ reason: VoiceModeMachine.PauseReason) -> String {
        switch reason {
        case .user: "Pausiert"
        case .silence: "Pausiert, nichts gehört"
        case .offline: "Keine Verbindung · pausiert"
        case .failed: "Das hat nicht geklappt · pausiert"
        }
    }
}

/// The one-time explanation before the first voice mode (SP5, "Der erste Start zeigt einmal, was der Modus tut").
struct VoiceModeExplanation: View {
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sprechmodus", systemImage: "waveform").font(.subheadline.weight(.semibold))
            Text("Tagwerk hört zu und sendet, was du sagst, nach einer kurzen Pause an ChatGPT. Bis dahin kannst du „Nicht senden“ tippen. Die Antwort wird vorgelesen, danach hört Tagwerk wieder zu.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Der Ton wird auf dem iPhone in Text umgewandelt. Änderungen führt Tagwerk erst aus, wenn du sie bestätigst.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Abbrechen", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("Starten", action: onStart).buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
