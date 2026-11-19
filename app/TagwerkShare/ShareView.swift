import SwiftUI
import TagwerkCore

/// The sheet of the share extension: check where the item goes and what it is called, then save it for the app.
struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("Wird gelesen …")
                case .failed(let message):
                    ContentUnavailableView {
                        Label(message, systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Abbrechen") { model.cancel() }
                    }
                case .saved:
                    ContentUnavailableView("Gesichert. Öffne Tagwerk, um es zu übernehmen.", systemImage: "checkmark.circle")
                case .ready, .saving:
                    form
                }
            }
            .navigationTitle("Tagwerk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.state == .ready || model.state == .saving {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { model.cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("In Tagwerk sichern") { Task { await model.save() } }
                            .disabled(!model.canSave || model.state == .saving)
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private var form: some View {
        Form {
            Section {
                preview
            }
            Section {
                Picker("Ablegen als", selection: $model.target) {
                    ForEach(model.payload?.availableTargets ?? [], id: \.self) { target in
                        Text(Self.name(of: target)).tag(target)
                    }
                }
            } footer: {
                if model.dropsFiles {
                    Text("Dateien werden nur bei Notizen übernommen.")
                }
            }
            Section {
                TextField("Titel", text: $model.title)
                if model.showsTextField {
                    TextField("Text", text: $model.text, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            if let thumbnail = model.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline).lineLimit(2)
                if let host = model.hostText {
                    Text(host).font(.subheadline).foregroundStyle(.secondary)
                } else if !model.fileNames.isEmpty {
                    Text(model.fileNames.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                } else if model.payload?.mail != nil {
                    Text("Mail").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func name(of target: ShareTarget) -> String {
        switch target {
        case .task: String(localized: "Aufgabe")
        case .note: String(localized: "Notiz")
        case .shopping: String(localized: "Einkauf")
        case .recipe: String(localized: "Rezept")
        case .mailTask: String(localized: "Mail zu Aufgabe")
        }
    }
}
