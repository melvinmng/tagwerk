import SwiftUI
import TagwerkCore

/// Back and forward arrows as one glass capsule with 44-pt targets (mockups PK2, EK1).
struct PageArrowCapsule: View {
    let backLabel: String
    let forwardLabel: String
    var canGoForward = true
    let onStep: (PageSwipe) -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow(.back, symbol: "chevron.left", label: backLabel)
            arrow(.forward, symbol: "chevron.right", label: forwardLabel)
                .disabled(!canGoForward)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func arrow(_ direction: PageSwipe, symbol: String, label: String) -> some View {
        Button { withAnimation(.snappy) { onStep(direction) } } label: {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer()
    }
}

/// "Heute" next to the arrows while another period is shown (mockups PK2, EK1).
struct PageTodayButton: View {
    let action: () -> Void

    var body: some View {
        Button("Heute") { withAnimation(.snappy) { action() } }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityShowsLargeContentViewer()
    }
}

/// Caption above a title with ▾ (mockups PK2, EK1): one VoiceOver element that opens the month calendar.
struct PageTitleLabel: View {
    let caption: String
    let title: String
    let isCurrent: Bool
    var titleFont: Font = .title3.bold()
    /// `false` keeps the title at full size; the plan header picks a shorter text instead of shrinking it.
    var titleScales = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The caption ("SA. 21. NOV. · KW 47") is wider than the space next to the arrows at the accessibility
            // sizes, so it wraps there instead of being cut off; at the other sizes it stays on one line.
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondaryText)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(titleFont).lineLimit(1).minimumScaleFactor(titleScales ? 0.8 : 1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondaryText)
            }
        }
    }
}
