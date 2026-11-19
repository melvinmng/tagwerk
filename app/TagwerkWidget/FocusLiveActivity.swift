import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The focus timer on the lock screen and in the Dynamic Island. The countdown runs on its own through
/// `Text(timerInterval:)`. Without a push server the activity cannot change itself at the end of a phase: it turns stale
/// at `phaseEnd` and then shows "Phase vorbei" with the three buttons; the next phase starts with a tap or when the app opens.
/// Look and wording are a first draft for the design round.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreenView(attributes: context.attributes, state: context.state, isOver: context.isStale)
                .widgetURL(FocusLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(FocusActivityText.phaseName(context.state, isOver: context.isStale), systemImage: FocusActivityText.symbol(context.state))
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusCountdown(state: context.state, isOver: context.isStale)
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.attributes.title.isEmpty {
                        Text(context.attributes.title).font(.caption).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FocusButtons(state: context.state, isOver: context.isStale)
                }
            } compactLeading: {
                Image(systemName: FocusActivityText.symbol(context.state))
            } compactTrailing: {
                FocusCountdown(state: context.state, isOver: context.isStale)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: FocusActivityText.symbol(context.state))
            }
            .widgetURL(FocusLink.url)
        }
    }
}

/// Texts and symbols of the focus Live Activity.
enum FocusActivityText {
    static func symbol(_ state: FocusActivityAttributes.ContentState) -> String {
        switch state.kind {
        case .work: "timer"
        case .shortBreak, .longBreak: "cup.and.saucer.fill"
        case .finished: "checkmark.circle.fill"
        }
    }

    static func phaseName(_ state: FocusActivityAttributes.ContentState, isOver: Bool) -> String {
        if isOver || state.kind == .finished { return String(localized: "Phase vorbei") }
        switch state.kind {
        case .work: return String(localized: "Fokus")
        case .shortBreak: return String(localized: "Kurze Pause")
        case .longBreak: return String(localized: "Lange Pause")
        case .finished: return String(localized: "Phase vorbei")
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

struct FocusLockScreenView: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(FocusActivityText.phaseName(state, isOver: isOver), systemImage: FocusActivityText.symbol(state))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if attributes.isPomodoro {
                    Text(verbatim: "\(state.round)/\(state.rounds)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                FocusCountdown(state: state, isOver: isOver)
                    .font(.largeTitle.monospacedDigit().weight(.semibold))
                Spacer()
                if !attributes.title.isEmpty {
                    Text(attributes.title).font(.callout).lineLimit(1).foregroundStyle(.secondary)
                }
            }
            FocusButtons(state: state, isOver: isOver)
        }
        .padding()
    }
}

/// "Pause" while working, "Erledigt / Weiter / Verschieben" when the phase is over.
struct FocusButtons: View {
    let state: FocusActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isOver || state.kind == .finished {
                Button(intent: FocusCompleteIntent()) { Label("Erledigt", systemImage: "checkmark") }
                Button(intent: FocusContinueIntent()) { Label("Weiter", systemImage: "forward.fill") }
                Button(intent: FocusPostponeIntent()) { Label("Verschieben", systemImage: "calendar") }
            } else if state.kind == .work {
                Button(intent: FocusPauseIntent()) {
                    Label(state.pausedRemaining == nil ? "Pausieren" : "Fortsetzen",
                          systemImage: state.pausedRemaining == nil ? "pause.fill" : "play.fill")
                }
            } else {
                Button(intent: FocusContinueIntent()) { Label("Pause überspringen", systemImage: "forward.fill") }
            }
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
    }
}
