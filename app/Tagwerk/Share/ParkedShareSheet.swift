import SwiftUI
import TagwerkCore

/// The list behind the row "Geteilt (n)": items that were offered several times without a decision. Each can be taken over
/// (it is offered again) or discarded with its files.
struct ParkedShareSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = environment.shareInbox
        NavigationStack {
            List {
                ForEach(model.parked) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline).lineLimit(2)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button("Übernehmen") {
                                model.accept(item.id)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Verwerfen", role: .destructive) { model.finish(item.id) }
                                .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if model.parked.isEmpty { ContentUnavailableView("Nichts geteilt", systemImage: "tray") }
            }
            .navigationTitle("Geteilt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
