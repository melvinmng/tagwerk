import SwiftUI

/// Confirmation after an action (mockup 1A): glass capsule with the title and one button whose ring
/// shows the remaining time. The button undoes the action by default; callers may give it another
/// title, symbol and hint (e.g. "Auf GitHub öffnen" after handing over an issue).
struct UndoCapsule: View {
    let title: String
    var caption: LocalizedStringResource = "Erledigt"
    var symbol = "checkmark.circle.fill"
    let duration: TimeInterval
    var actionTitle: LocalizedStringResource = "Rückgängig"
    var actionSymbol = "arrow.uturn.backward"
    var actionHint: LocalizedStringResource = "Markiert die Aufgabe wieder als offen"
    /// Spoken on appear; `nil` keeps "<caption>: <title>. Rückgängig verfügbar."
    var announcement: String? = nil
    /// Action of the button.
    let onUndo: () -> Void
    let onExpire: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remaining: CGFloat = 1

    var body: some View {
        ViewThatFits {
            HStack(spacing: 12) { label; Spacer(minLength: 8); undoButton }
            VStack(alignment: .leading, spacing: 10) { label; undoButton }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal)
        .padding(.bottom, 4)
        .onAppear {
            let spokenCaption = String(localized: caption)
            AccessibilityNotification.Announcement(
                announcement ?? String(localized: "\(spokenCaption): \(title). Rückgängig verfügbar.")).post()
            if !reduceMotion {
                withAnimation(.linear(duration: duration)) { remaining = 0 }
            }
        }
        .task {
            // Screen-reader users get no time limit; the capsule stays until the next action.
            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { onExpire() }
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.3), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: remaining)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: actionSymbol).font(.caption.weight(.bold))
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                Text(actionTitle).fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .accessibilityHint(Text(actionHint))
    }
}

/// "Vergeben" after an issue left the user's lists (mockup ZD1): number and people, with the only way
/// to the issue on GitHub. There is nothing to undo; the capsule stays 8 seconds.
struct HandedOverCapsule: View {
    let model: TaskListModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let notice = model.lastHandedOver {
            UndoCapsule(title: notice.title,
                        caption: notice.caption, symbol: notice.symbol, duration: 8,
                        actionTitle: "Auf GitHub öffnen", actionSymbol: "arrow.up.right",
                        actionHint: "Öffnet das Issue im Browser",
                        announcement: notice.announcement,
                        onUndo: {
                            if let url = notice.url { openURL(url) }
                            model.dismissHandedOver()
                        },
                        onExpire: { if model.lastHandedOver == notice { model.dismissHandedOver() } })
                .id(notice.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
