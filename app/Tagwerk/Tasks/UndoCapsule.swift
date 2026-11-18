import SwiftUI

/// Confirmation after completing a task (mockup 1A): glass capsule with the title and an undo
/// button whose ring shows the remaining time.
struct UndoCapsule: View {
    let title: String
    var caption: LocalizedStringResource = "Erledigt"
    var symbol = "checkmark.circle.fill"
    let duration: TimeInterval
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
            AccessibilityNotification.Announcement(String(localized: "\(spokenCaption): \(title). Rückgängig verfügbar.")).post()
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
                    Image(systemName: "arrow.uturn.backward").font(.caption.weight(.bold))
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                Text("Rückgängig").fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Markiert die Aufgabe wieder als offen")
    }
}
