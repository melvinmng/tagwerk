import SwiftUI
import TagwerkCore

/// "Alle Vorschläge besprechen" (plan ki-vorschlaege-anpassen, task E2, AN13a): the open suggestions of one planning and the
/// input line (`FollowUpBar`) to write about all of them at once. The request is the one of the conversation about one
/// suggestion, without a highlighted one; Tagwerk checks every change locally and keeps what the user moved. Nothing reaches a
/// calendar before "Übernehmen" in the plan bar.
struct PlanBatchConversationSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let batchID: UUID
    @FocusState private var focused: Bool

    private var planner: AIPlanner { environment.planner }
    private var batch: SuggestionBatch? { environment.planning.suggestionBatches.first { $0.id == batchID } }

    static var quickReplies: [String] {
        [String(localized: "Alles früher am Tag"), String(localized: "Weniger am Abend"), String(localized: "Gleichmäßiger verteilen")]
    }

    private var state: FollowUpState {
        if planner.revisingID == batchID { return .sending }
        if let error = planner.revisionError { return .failed(error) }
        return .ready
    }

    var body: some View {
        NavigationStack {
            List {
                if let batch {
                    Section("Offene Vorschläge") {
                        ForEach(batch.suggestions.filter { $0.kind != .dayChange }) { suggestion in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                Text(AIPlanner.positionText(suggestion.position, calendar: environment.planning.calendar))
                                    .font(.subheadline).foregroundStyle(.secondaryText)
                                if suggestion.isMovedByUser {
                                    Text("von dir verschoben, bleibt").font(.caption).foregroundStyle(.secondaryText)
                                }
                            }
                        }
                    }
                    Section {
                        FollowUpBar(availability: environment.ai.isSignedIn ? .available : .hidden, state: state, place: .planning,
                                    quickReplies: Self.quickReplies, placeholder: "Zu allen Vorschlägen etwas sagen …",
                                    footer: Text("Senden gibt alle Vorschläge dieser Planung, deine Änderungen, deine Vorgaben und die Termine dieser Tage an ChatGPT."),
                                    isFocused: $focused, onSend: { message in Task { await planner.revise(batch: batch, comment: message) } },
                                    onRetry: { if let last = lastMessage { Task { await planner.revise(batch: batch, comment: last) } } }) {
                            exchange(batch)
                        }
                    } header: {
                        Label("Mit ChatGPT besprechen", systemImage: "sparkles")
                    }
                } else {
                    Text("Die Planung gibt es nicht mehr.").foregroundStyle(.secondaryText)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Alle Vorschläge besprechen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private var lastMessage: String? { batch?.conversation?.last { $0.role == .user }?.text }

    /// The answers about this whole planning: what changed, what Tagwerk did not take, the sentence, and "Rückgängig".
    @ViewBuilder
    private func exchange(_ batch: SuggestionBatch) -> some View {
        let answers = (batch.conversation ?? []).filter { $0.suggestionID == nil }
        ForEach(answers) { message in
            if message.role == .user {
                Text(message.text).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    let changes = message.changes ?? []
                    Label(changes.isEmpty ? "Nichts geändert" : "\(changes.count) Vorschläge geändert", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.purpleText)
                    ForEach(changes, id: \.self) { Text($0).font(.caption) }
                    ForEach(message.rejected ?? [], id: \.self) { line in
                        Label(line, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orangeText)
                    }
                    if !message.text.isEmpty { Text("„\(message.text)“").font(.caption).foregroundStyle(.purpleText) }
                    if message.id == answers.last?.id, batch.revisionUndo != nil {
                        Button("Rückgängig") { Task { await planner.undoRevision(of: batch.id) } }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }
}
