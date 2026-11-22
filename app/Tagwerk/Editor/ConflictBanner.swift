import SwiftUI

/// Conflict card (mockup 2A): what changed at the source, where it overlaps with the user's edits,
/// and what each button does.
struct ConflictBanner: View {
    let sourceName: String
    let changes: [ConflictChange]
    let onReload: () -> Void
    let onSaveAnyway: () -> Void
    @AccessibilityFocusState private var headerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auf \(sourceName) geändert").font(.headline)
                    Text(changes.isEmpty ? String(localized: "Seit dem Öffnen wurde die Aufgabe geändert.")
                                         : String(localized: "Seit dem Öffnen wurden \(changes.count) Felder geändert."))
                        .font(.subheadline).foregroundStyle(.secondaryText)
                }
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
            }
            .accessibilityFocused($headerFocused)

            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(change.field) {
                        HStack(spacing: 4) {
                            Text(change.before).strikethrough().foregroundStyle(.secondaryText)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondaryText)
                            Text(change.after)
                        }
                    }
                    if let mine = change.mine {
                        Label("Du hast \(mine) gewählt", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orangeText)
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }

            ViewThatFits {
                HStack { buttons }
                VStack(alignment: .leading) { buttons }
            }

            Text(footer).font(.caption).foregroundStyle(.secondaryText)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.45)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Konflikt")
        .onAppear { headerFocused = true }
    }

    @ViewBuilder private var buttons: some View {
        // Explicit styles: inside a Form row, default buttons all fire on one tap.
        Button("Neu laden", action: onReload)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        Button("Trotzdem sichern", action: onSaveAnyway)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
    }

    private var footer: String {
        let overlap = changes.contains { $0.mine != nil }
        return overlap
            ? String(localized: "„Neu laden“ verwirft deine Änderungen. „Trotzdem sichern“ schreibt deine Werte und überschreibt dabei die markierten Felder auf \(sourceName).")
            : String(localized: "„Neu laden“ verwirft deine Änderungen. „Trotzdem sichern“ schreibt nur deine Änderungen und überschreibt nichts auf \(sourceName).")
    }
}
