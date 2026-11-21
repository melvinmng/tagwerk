import AIKit
import SwiftUI
import TagwerkCore

/// "Änderung ansehen" of a note card (mockup NC2b): for a revision the text before, after and the changed lines, for a new
/// note or a deletion the text. It hangs on the chat, not on the card row. "Verwerfen" and the confirm button close it and
/// answer the card like the buttons on the card do; "Schließen" leaves the card open.
struct NoteChangeSheet: View {
    let card: AssistantModel.ActionCard
    let detail: AssistantModel.NoteCardDetail
    let onDecline: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var view: Perspective = .changes

    private enum Perspective: String, CaseIterable, Identifiable {
        case before, after, changes
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .before: "Vorher"
            case .after: "Nachher"
            case .changes: "Änderungen"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if case .update = detail {
                    Picker("Ansicht", selection: $view) {
                        ForEach(Perspective.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                }
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                buttons
            }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        switch detail {
        case .update(_, let before, let after):
            switch view {
            case .before: Text(before).textSelection(.enabled)
            case .after: Text(after).textSelection(.enabled)
            case .changes: changeLines(old: before, new: after)
            }
        case .create(let text), .delete(let text):
            Text(text).textSelection(.enabled)
        }
    }

    /// The lines with "+" and "−", colour and an accessibility label; nothing is struck through.
    private func changeLines(old: String, new: String) -> some View {
        let lines = NoteDiff.lines(old: old, new: new)
        return LazyVStack(alignment: .leading, spacing: 4) {
            if lines.allSatisfy({ $0.kind == .same }) {
                Text("Keine Änderung").foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(symbol(line.kind)).font(.body.monospaced()).frame(width: 16)
                    Text(line.text.isEmpty ? " " : line.text)
                }
                .foregroundStyle(color(line.kind))
                .padding(.vertical, 2)
                .background(background(line.kind), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label(line))
            }
        }
    }

    private func symbol(_ kind: NoteDiff.Line.Kind) -> String {
        switch kind {
        case .same: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private func color(_ kind: NoteDiff.Line.Kind) -> Color {
        switch kind {
        case .same: .primary
        case .added: .green
        case .removed: .red
        }
    }

    private func background(_ kind: NoteDiff.Line.Kind) -> Color {
        switch kind {
        case .same: .clear
        case .added: .green.opacity(0.12)
        case .removed: .red.opacity(0.12)
        }
    }

    private func label(_ line: NoteDiff.Line) -> String {
        switch line.kind {
        case .same: line.text
        case .added: String(localized: "neu: \(line.text)")
        case .removed: String(localized: "entfernt: \(line.text)")
        }
    }

    private var buttons: some View {
        HStack {
            Button("Verwerfen") {
                dismiss()
                onDecline()
            }
            .buttonStyle(.bordered)
            Spacer()
            Button(role: card.isDestructive ? .destructive : nil) {
                dismiss()
                onConfirm()
            } label: {
                Text(card.confirmTitle ?? String(localized: "Bestätigen"))
            }
            .buttonStyle(.borderedProminent)
            .tint(card.isDestructive ? .red : nil)
        }
        .padding()
        .background(.bar)
    }
}

/// The note card whose proposal the sheet shows.
struct NoteDetailRequest: Identifiable {
    let call: ToolCall
    let card: AssistantModel.ActionCard
    var id: String { call.id }
}
