import SwiftUI
import TagwerkCore

/// An AI suggestion in the hour grid (mockup W1): purple, dashed, not draggable, with ✓ / ✕.
struct SuggestionBlock: View {
    let suggestion: PlanSuggestion
    let timeText: String
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
            SuggestionButtons(onAccept: onAccept, onDismiss: onDismiss)
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
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onAccept) { Image(systemName: "checkmark.circle.fill").font(.title3) }
                .accessibilityLabel("Übernehmen")
            Button(action: onDismiss) { Image(systemName: "xmark.circle").font(.title3) }
                .accessibilityLabel("Verwerfen")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.purple)
    }
}

/// A suggestion as a list row (mockups W3, X1, X2): dashed, without grip, reason on tap.
struct SuggestionRow: View {
    @Environment(AppEnvironment.self) private var environment
    let suggestion: PlanSuggestion
    @State private var showsReason = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(suggestion.title, systemImage: "sparkles").font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if showsReason && !suggestion.reason.isEmpty {
                    Text("„\(suggestion.reason)“").font(.caption).foregroundStyle(.purple)
                }
            }
            Spacer(minLength: 0)
            SuggestionButtons(onAccept: { Task { await environment.planner.accept(suggestion) } },
                              onDismiss: { Task { await environment.planner.dismiss(suggestion) } })
        }
        .padding(8)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .foregroundStyle(.purple)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showsReason.toggle() } }
    }

    private var detail: String {
        var parts = ["Vorschlag"]
        if let start = suggestion.startMinutes { parts.append(AIPlanner.time(start)) }
        if let minutes = suggestion.minutes { parts.append(CapacityText.duration(minutes)) }
        return parts.joined(separator: " · ")
    }
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
