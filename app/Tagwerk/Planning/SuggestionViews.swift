import SwiftUI
import TagwerkCore

/// An AI suggestion in the hour grid (mockup W1): purple, dashed, not draggable, with ✓ / ✕.
struct SuggestionBlock: View {
    let suggestion: PlanSuggestion
    let timeText: String
    var acceptEnabled = true
    let onOpen: () -> Void
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Label(suggestion.title, systemImage: "sparkles").font(.caption.weight(.semibold)).lineLimit(2)
                Text(timeText + " · Vorschlag").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            SuggestionButtons(acceptEnabled: acceptEnabled, onAccept: onAccept, onDismiss: onDismiss)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .foregroundStyle(.purple)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vorschlag, \(suggestion.title), \(timeText)")
        .accessibilityAction(named: "Übernehmen", onAccept)
        .accessibilityAction(named: "Verwerfen", onDismiss)
    }
}

/// ✓ and ✕ of a suggestion.
struct SuggestionButtons: View {
    var acceptEnabled = true
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onAccept) { Image(systemName: "checkmark.circle.fill").font(.title3) }
                .disabled(!acceptEnabled)
                .opacity(acceptEnabled ? 1 : 0.35)
                .accessibilityLabel("Übernehmen")
            Button(action: onDismiss) { Image(systemName: "xmark.circle").font(.title3) }
                .accessibilityLabel("Verwerfen")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.purple)
    }
}

/// A suggestion as a list row (mockups W3, X1, X2; AO1 longer day; "↷" move): dashed, without grip,
/// reason on tap. A block that needs a longer day waits for it (mockup AB1).
struct SuggestionRow: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    @State private var showsReason = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(SuggestionText.title(suggestion, calendar: environment.planning.calendar), systemImage: SuggestionText.symbol(suggestion))
                    .font(.subheadline)
                Text(SuggestionText.detail(suggestion, planning: environment.planning)).font(.caption).foregroundStyle(.secondary)
                if isWaiting {
                    Label("braucht die längere Arbeitszeit", systemImage: "arrow.turn.down.right").font(.caption2)
                }
                if showsReason && !suggestion.reason.isEmpty {
                    Text("„\(suggestion.reason)“").font(.caption).foregroundStyle(.purple)
                }
            }
            Spacer(minLength: 0)
            SuggestionButtons(acceptEnabled: !isWaiting,
                              onAccept: { Task { await environment.planner.accept(suggestion) } },
                              onDismiss: { Task { await environment.planner.dismiss(suggestion) } })
        }
        .padding(8)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .foregroundStyle(.purple)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showsReason.toggle() } }
    }

    private var isWaiting: Bool { SuggestionText.isWaiting(suggestion, planning: environment.planning) }
}

/// Sheet of one suggestion (mockup W1, opened by tapping the block): when, reason, accept or dismiss.
struct SuggestionSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let suggestion: PlanSuggestion

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Aufgabe", value: suggestion.title)
                    LabeledContent("Wann", value: SuggestionText.when(suggestion, calendar: environment.planning.calendar))
                }
                if !suggestion.reason.isEmpty {
                    Section("Begründung") {
                        Label("„\(suggestion.reason)“", systemImage: "sparkles").foregroundStyle(.purple)
                    }
                }
                Section {
                    Button("Übernehmen") {
                        Task { await environment.planner.accept(suggestion); dismiss() }
                    }
                    Button("Verwerfen", role: .destructive) {
                        Task { await environment.planner.dismiss(suggestion); dismiss() }
                    }
                } footer: {
                    Text("Erst „Übernehmen“ legt den Block im Plan-Kalender an.")
                }
            }
            .navigationTitle("Vorschlag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// A move at the task it concerns (proposal 2026-11-18, §5): dashed, "↷ Fr 20.", ✓ / ✕.
struct MoveSuggestionRow: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    @State private var showsReason = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title).font(.subheadline).lineLimit(2)
                Label("nach \(suggestion.day.startDate(in: environment.planning.calendar).formatted(.dateTime.weekday(.abbreviated).day()))",
                      systemImage: "arrow.uturn.right")
                    .font(.caption).foregroundStyle(.purple)
                if showsReason && !suggestion.reason.isEmpty {
                    Text("„\(suggestion.reason)“").font(.caption).foregroundStyle(.purple)
                }
            }
            Spacer(minLength: 0)
            SuggestionButtons(onAccept: { Task { await environment.planner.accept(suggestion) } },
                              onDismiss: { Task { await environment.planner.dismiss(suggestion) } })
        }
        .padding(8)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showsReason.toggle() } }
    }
}

/// The target day's side of a move (week, §5): a dashed ghost row without buttons.
struct MoveGhostRow: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion

    var body: some View {
        let from = suggestion.fromDay.map { $0.startDate(in: environment.planning.calendar).formatted(.dateTime.weekday(.abbreviated).day()) } ?? ""
        Label("von \(from) · \(suggestion.title)", systemImage: "arrow.uturn.right")
            .font(.subheadline)
            .foregroundStyle(.purple.opacity(0.7))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
    }
}
