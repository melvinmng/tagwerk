import SwiftUI
import TagwerkCore

/// "▶ Fokus" on the time block that is running now, or else on the next one of the day (FO4b). A tap starts the timer at
/// once for the rest of the block, without the start sheet. While a session runs, the block of that session shows a timer
/// symbol instead and every other block shows nothing. In a narrow column only the symbol is shown.
struct FocusPlanButton: View {
    @Environment(AppEnvironment.self) private var environment
    let event: CalendarEvent
    let model: PlanningModel
    /// Narrow column: the symbol without the word.
    var iconOnly = false

    /// The tappable area: at least 44 pt wide and 28 pt high, whatever the visible size is.
    static let minimumSize = CGSize(width: 44, height: 28)

    var body: some View {
        if environment.focus.isRunning(forBlockID: event.id) {
            Image(systemName: "timer").font(.caption.weight(.semibold)).foregroundStyle(.secondaryText)
                .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
                .accessibilityLabel("Fokus läuft")
        } else if !environment.focus.isRunning {
            Button {
                let task = model.linkedTask(eventID: event.id)
                Task { await environment.focus.start(task: task, block: event, choice: .untilBlockEnd) }
            } label: {
                label.frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fokus starten")
            .accessibilityIdentifier(AccessibilityID.Focus.planButton)
        }
    }

    @ViewBuilder
    private var label: some View {
        // Text in the primary colour on a light fill: the accent colour on its own tint would stay under 4.5:1.
        if iconOnly {
            Image(systemName: "play.fill").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
        } else {
            HStack(spacing: 3) {
                Image(systemName: "play.fill").foregroundStyle(Color.accentColor)
                Text("Fokus").foregroundStyle(.primary)
            }
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
        }
    }
}
