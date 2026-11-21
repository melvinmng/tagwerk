import SwiftUI
import TagwerkCore

/// The focus timer sheet: remaining time, phase, round and the controls. A first draft for the design round (#188).
struct FocusTimerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var askingToStop = false

    private var focus: FocusTimerModel { environment.focus }

    var body: some View {
        NavigationStack {
            Group {
                if let session = focus.session {
                    // One update per second, only while this sheet is on screen.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let snapshot = focus.snapshot(at: context.date) {
                            content(session: session, snapshot: snapshot)
                        }
                    }
                } else {
                    ContentUnavailableView("Kein Fokus läuft", systemImage: "timer")
                }
            }
            .navigationTitle("Fokus-Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Schließen") { focus.isPresented = false } }
            }
            .confirmationDialog("Fokus abbrechen?", isPresented: $askingToStop, titleVisibility: .visible) {
                Button("Abbrechen", role: .destructive) { Task { await focus.stop() } }
                Button("Weitermachen", role: .cancel) {}
            } message: {
                Text("Der Baustein bleibt erhalten und wird als vorzeitig beendet markiert.")
            }
        }
    }

    private func content(session: FocusTimerModel.Session, snapshot: FocusTimerSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(FocusTimerText.phaseName(snapshot.phase))
                        .font(.title3.weight(.semibold))
                    if let round = FocusTimerText.roundText(phase: snapshot.phase, settings: session.state.settings) {
                        Text(round).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if snapshot.phase == .finished {
                    Text(FocusTimerText.focusedText(seconds: snapshot.focusedSeconds))
                        .font(.largeTitle.weight(.semibold))
                } else {
                    Text(FocusTimerText.clock(snapshot.remainingSeconds))
                        .font(.system(size: 72, weight: .semibold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel(FocusTimerText.spoken(snapshot.remainingSeconds))
                    ProgressView(value: progress(snapshot))
                        .padding(.horizontal)
                        .accessibilityHidden(true)
                    if snapshot.isPaused { Label("Pausiert", systemImage: "pause.circle").foregroundStyle(.secondary) }
                }
                if !session.title.isEmpty {
                    Text(session.title).font(.headline).multilineTextAlignment(.center)
                }
                controls(session: session, snapshot: snapshot)
            }
            .padding()
        }
    }

    private func progress(_ snapshot: FocusTimerSnapshot) -> Double {
        guard snapshot.phaseSeconds > 0 else { return 1 }
        return min(1, max(0, 1 - Double(snapshot.remainingSeconds) / Double(snapshot.phaseSeconds)))
    }

    @ViewBuilder
    private func controls(session: FocusTimerModel.Session, snapshot: FocusTimerSnapshot) -> some View {
        VStack(spacing: 12) {
            if snapshot.phase == .finished {
                if session.taskKey != nil {
                    Button { Task { await focus.finish(.complete) } } label: {
                        Label("Erledigt", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button { Task { await focus.finish(.keepGoing) } } label: {
                    Label("Weiter", systemImage: "forward.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if session.taskKey != nil {
                    Button { Task { await focus.finish(.postpone) } } label: {
                        Label("Verschieben", systemImage: "calendar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Beenden") { Task { await focus.stop() } }
                    .buttonStyle(.borderless)
            } else {
                Button {
                    Task { await snapshot.isPaused ? focus.resume() : focus.pause() }
                } label: {
                    Label(snapshot.isPaused ? "Fortsetzen" : "Pausieren", systemImage: snapshot.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if snapshot.phase.isBreak {
                    Button { Task { await focus.skipBreak() } } label: {
                        Label("Pause überspringen", systemImage: "forward.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Beenden", role: .destructive) { askToStop(snapshot) }
                    .buttonStyle(.borderless)
            }
        }
    }

    /// Within the first minute nothing is left of the session, so no question is needed.
    private func askToStop(_ snapshot: FocusTimerSnapshot) {
        if snapshot.focusedSeconds < FocusReward.discardSeconds {
            Task { await focus.stop() }
        } else {
            askingToStop = true
        }
    }
}
