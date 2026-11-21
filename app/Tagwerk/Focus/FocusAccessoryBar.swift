import SwiftUI
import TagwerkCore

/// One line above the tab bar while a focus session runs: progress ring, title, remaining time and the pause button
/// (FO5b). A tap opens the timer sheet. Green with the name of the break during a break. In the small placement of the tab
/// bar (the bar is minimised) only the ring and the remaining time are shown.
struct FocusAccessoryBar: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var focus: FocusTimerModel { environment.focus }

    var body: some View {
        if let session = focus.session {
            // One update per second, only for the bar.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let snapshot = focus.snapshot(at: context.date) {
                    bar(session: session, snapshot: snapshot)
                }
            }
        }
    }

    private func bar(session: FocusTimerModel.Session, snapshot: FocusTimerSnapshot) -> some View {
        let isBreak = snapshot.phase.isBreak
        let tint: Color = isBreak ? .green : .accentColor
        let isCompact = placement == .inline
        let title = isBreak ? FocusTimerText.phaseName(snapshot.phase) : (session.title.isEmpty ? String(localized: "Fokus") : session.title)
        let fraction = snapshot.phaseSeconds > 0 ? min(1, max(0, Double(snapshot.remainingSeconds) / Double(snapshot.phaseSeconds))) : 0
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            if !isCompact {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
            }
            Text(snapshot.phase == .finished ? FocusTimerText.phaseName(.finished) : FocusTimerText.clock(snapshot.remainingSeconds))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
            if !isCompact && snapshot.phase != .finished {
                Button {
                    Task { await snapshot.isPaused ? focus.resume() : focus.pause() }
                } label: {
                    Image(systemName: snapshot.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { focus.isPresented = true }
        // One element for VoiceOver: the state as a sentence, pausing as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Focus.bar)
        .accessibilityLabel(Text(FocusTimerText.barAccessibility(title: isBreak ? "" : session.title,
                                                                 remainingSeconds: snapshot.remainingSeconds, phase: snapshot.phase)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(snapshot.isPaused ? "Fortsetzen" : "Pausieren")) {
            Task { await snapshot.isPaused ? focus.resume() : focus.pause() }
        }
    }
}
