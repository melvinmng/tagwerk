import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The focus timer on the lock screen and in the Dynamic Island (FO10b, FO11b). The task comes first, the countdown runs on
/// its own through `Text(timerInterval:)` and `ProgressView(timerInterval:)`. Without a push server the activity cannot change
/// itself at the end of a phase: it turns stale at `phaseEnd` and then shows what was reached with the next step; the state
/// is brought in line when a button is tapped or the app opens. The running view always offers "Erledigt" next to the pause
/// button, so the way to finish does not depend on how punctually iOS turns the activity stale (L1 of the device test).
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreenView(attributes: context.attributes, state: context.state, isOver: context.isStale)
                .widgetURL(FocusLink.url)
        } dynamicIsland: { context in
            let tint = FocusActivityText.tint(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(FocusActivityText.title(context.attributes))
                            .font(.headline)
                            .lineLimit(1)
                        Text(FocusActivityText.expandedSubline(context.state, isOver: context.isStale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusCountdown(state: context.state, isOver: context.isStale)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.leading) {
                    FocusRing(state: context.state, isOver: context.isStale).frame(width: 34, height: 34)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FocusButtons(attributes: context.attributes, state: context.state, isOver: context.isStale)
                }
            } compactLeading: {
                FocusRing(state: context.state, isOver: context.isStale).frame(width: 20, height: 20)
            } compactTrailing: {
                FocusCountdown(state: context.state, isOver: context.isStale)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                FocusRing(state: context.state, isOver: context.isStale).frame(width: 20, height: 20)
            }
            .keylineTint(tint)
            .widgetURL(FocusLink.url)
        }
    }
}

/// Texts, symbols and colours of the focus Live Activity.
enum FocusActivityText {
    /// Focus in the accent blue, breaks in green; the colours tell the activity apart from the system timer.
    static func tint(_ state: FocusActivityAttributes.ContentState) -> Color {
        switch state.kind {
        case .work: .blue
        case .shortBreak, .longBreak: .green
        case .finished: .green
        }
    }

    /// The task, or "Fokus" for a free session.
    static func title(_ attributes: FocusActivityAttributes) -> String {
        attributes.title.isEmpty ? String(localized: "Fokus") : attributes.title
    }

    static func phaseName(_ state: FocusActivityAttributes.ContentState) -> String {
        switch state.kind {
        case .work: String(localized: "Fokus")
        case .shortBreak: String(localized: "Kurze Pause")
        case .longBreak: String(localized: "Lange Pause")
        case .finished: String(localized: "Geschafft")
        }
    }

    /// "Fokus · Runde 1 von 4 · bis 14:51"; "pausiert" instead of the end while paused.
    static func subline(_ attributes: FocusActivityAttributes, _ state: FocusActivityAttributes.ContentState) -> String {
        var parts = [phaseName(state)]
        if attributes.isPomodoro && state.kind != .finished { parts.append(String(localized: "Runde \(state.round) von \(state.rounds)")) }
        if let end = state.phaseEnd {
            parts.append(String(localized: "bis \(end.formatted(date: .omitted, time: .shortened))"))
        } else if state.pausedRemaining != nil {
            parts.append(String(localized: "pausiert"))
        }
        return parts.joined(separator: " · ")
    }

    /// The Dynamic Island's line: "Fokus · bis 14:51", or what was reached once the phase is over.
    static func expandedSubline(_ state: FocusActivityAttributes.ContentState, isOver: Bool) -> String {
        if isOver || state.kind == .finished { return reached(state) }
        var parts = [phaseName(state)]
        if let end = state.phaseEnd {
            parts.append(String(localized: "bis \(end.formatted(date: .omitted, time: .shortened))"))
        } else if state.pausedRemaining != nil {
            parts.append(String(localized: "pausiert"))
        }
        return parts.joined(separator: " · ")
    }

    /// "25 min Fokus geschafft ✓" after a work phase, "Pause vorbei" after a break.
    static func reached(_ state: FocusActivityAttributes.ContentState) -> String {
        switch state.kind {
        case .shortBreak, .longBreak:
            return String(localized: "Pause vorbei")
        case .work, .finished:
            guard let seconds = state.phaseSeconds, state.kind == .work else { return String(localized: "Fokus geschafft ✓") }
            return String(localized: "\(seconds / 60) min Fokus geschafft ✓")
        }
    }
}

/// The remaining time of the phase.
struct FocusCountdown: View {
    let state: FocusActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        if let end = state.phaseEnd, !isOver, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else if let remaining = state.pausedRemaining {
            Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
        } else {
            Text(verbatim: "0:00")
        }
    }
}

/// The progress of the phase as a ring (Dynamic Island): it empties with the running clock and stands still while paused.
struct FocusRing: View {
    let state: FocusActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        let tint = FocusActivityText.tint(state)
        if let end = state.phaseEnd, !isOver, end > .now, let seconds = state.phaseSeconds, seconds > 0 {
            ProgressView(timerInterval: end.addingTimeInterval(-Double(seconds))...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
        } else {
            let fraction = state.pausedRemaining.flatMap { remaining in state.phaseSeconds.map { Double(remaining) / Double(max($0, 1)) } } ?? (isOver ? 0 : 1)
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: min(1, max(0, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// The bar of the phase on the lock screen; fixed while paused.
struct FocusProgressBar: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        let tint = FocusActivityText.tint(state)
        if let end = state.phaseEnd, let seconds = state.phaseSeconds, seconds > 0, end > .now {
            ProgressView(timerInterval: end.addingTimeInterval(-Double(seconds))...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(tint)
        } else if let remaining = state.pausedRemaining, let seconds = state.phaseSeconds, seconds > 0 {
            ProgressView(value: Double(remaining), total: Double(seconds)).tint(tint)
        }
    }
}

struct FocusLockScreenView: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let isOver: Bool

    private var isDone: Bool { isOver || state.kind == .finished }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(FocusActivityText.title(attributes))
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            if isDone {
                Text(FocusActivityText.reached(state))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(FocusActivityText.subline(attributes, state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    FocusCountdown(state: state, isOver: isOver)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FocusActivityText.tint(state))
                }
                FocusProgressBar(state: state)
            }
            FocusButtons(attributes: attributes, state: state, isOver: isOver)
        }
        .padding()
    }
}

/// Running: pause (or skip the break) and "Erledigt". Phase over: "Erledigt" and the next step, which is "Pause starten ·
/// 5 min" while a break follows and "Weiter" otherwise. "Verschieben" stays in the app. Below accessibility sizes the
/// buttons sit side by side, above them one under the other (L3).
struct FocusButtons: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let isOver: Bool

    private var isDone: Bool { isOver || state.kind == .finished }
    private var showsDone: Bool { attributes.hasTask != false }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var buttons: some View {
        if isDone {
            // The phase is over: "Erledigt" closes the session also without a task.
            Button(intent: FocusCompleteIntent()) { Label("Erledigt", systemImage: "checkmark") }
            if let next = state.nextKind, next == .shortBreak || next == .longBreak, let minutes = state.nextPhaseMinutes {
                Button(intent: FocusShowCurrentIntent()) { Label("Pause starten · \(minutes) min", systemImage: "cup.and.saucer.fill") }
            } else {
                Button(intent: FocusContinueIntent()) { Label("Weiter", systemImage: "forward.fill") }
            }
        } else {
            if state.kind == .work || state.pausedRemaining != nil {
                Button(intent: FocusPauseIntent()) {
                    Label(state.pausedRemaining == nil ? "Pausieren" : "Fortsetzen",
                          systemImage: state.pausedRemaining == nil ? "pause.fill" : "play.fill")
                }
            } else {
                Button(intent: FocusContinueIntent()) { Label("Pause überspringen", systemImage: "forward.fill") }
            }
            if showsDone {
                Button(intent: FocusCompleteIntent()) { Label("Erledigt", systemImage: "checkmark") }
            }
        }
    }
}
