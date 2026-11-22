import SwiftUI
import TagwerkCore

/// The sheet of the share extension: choose where the item goes, check its title, then save it for the app.
struct ShareView: View {
    @Bindable var model: ShareModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                case .saved(let target):
                    confirmation(for: target)
                case .ready, .saving:
                    form
                }
            }
            .navigationTitle("In Tagwerk sichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.state == .ready || model.state == .saving {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { model.cancel() }
                    }
                }
            }
        }
        // The return key of the single-line title field; set at the root so it reaches every field of the sheet.
        .submitLabel(.done)
        .task { await model.load() }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                preview
            }
            Section {
                tiles
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            } footer: {
                hints
            }
            Section {
                TextField("Titel", text: $model.title)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.save() }
            } label: {
                Text("Sichern").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSave || model.state == .saving)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: Tiles

    private var targets: [ShareTarget] { model.payload?.availableTargets ?? [] }

    /// One row of tiles; from the accessibility sizes on two columns, so the names stay readable.
    private var tiles: some View {
        let columnCount = dynamicTypeSize >= .accessibility1 ? 2 : max(targets.count, 1)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(targets, id: \.self) { target in
                tile(for: target)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tile(for target: ShareTarget) -> some View {
        let isSelected = model.target == target
        return Button {
            model.target = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: ShareSheetText.symbol(for: target)).font(.title3)
                Text(Self.tileName(of: target, among: targets.count))
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(of: target))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Hints

    @ViewBuilder
    private var hints: some View {
        let lines = ShareSheetText.hints(target: model.target, hasFiles: model.hasFiles, hasText: model.hasText, hasURL: model.hasURL)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { hint in
                    Text(Self.text(of: hint))
                }
            }
        }
    }

    // MARK: Confirmation

    /// Names the target, so it is clear where the item went; a tap closes the sheet right away.
    private func confirmation(for target: ShareTarget) -> some View {
        Button {
            model.finish()
        } label: {
            ContentUnavailableView {
                Label(Self.confirmationTitle(of: target), systemImage: "checkmark.circle")
            } description: {
                Text("Tagwerk zeigt es dir beim nächsten Öffnen.")
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Preview

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
                    Text(host).font(.subheadline).foregroundStyle(.secondaryText)
                } else if !model.fileNames.isEmpty {
                    Text(model.fileNames.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondaryText).lineLimit(2)
                } else if model.payload?.mail != nil {
                    Text("Mail").font(.subheadline).foregroundStyle(.secondaryText)
                }
            }
        }
    }

    // MARK: Texts

    static func name(of target: ShareTarget) -> String {
        switch target {
        case .task: String(localized: "Aufgabe")
        case .note: String(localized: "Notiz")
        case .shopping: String(localized: "Einkauf")
        case .recipe: String(localized: "Rezept")
        case .mailTask: String(localized: "Mail zu Aufgabe")
        }
    }

    /// The name on a tile: with five tiles in one row "Mail zu Aufgabe" does not fit, so it reads "Mail".
    static func tileName(of target: ShareTarget, among count: Int) -> String {
        target == .mailTask && count >= 5 ? String(localized: "Mail") : name(of: target)
    }

    static func confirmationTitle(of target: ShareTarget) -> String {
        switch target {
        case .task: String(localized: "Als Aufgabe gesichert")
        case .note: String(localized: "Als Notiz gesichert")
        case .shopping: String(localized: "Für die Einkaufsliste gesichert")
        case .recipe: String(localized: "Als Rezept gesichert")
        case .mailTask: String(localized: "Mail gesichert")
        }
    }

    static func text(of hint: ShareHint) -> String {
        switch hint {
        case .recipeChoiceLater:
            String(localized: "Text und Link gehen mit. In Tagwerk wählst du, ob die Zutaten auf die Einkaufsliste kommen.")
        case .textAndLink: String(localized: "Text und Link gehen mit.")
        case .linesBecomeItems: String(localized: "Jede Zeile wird ein Artikel.")
        case .mailContinuesInApp: String(localized: "Tagwerk zeigt dir die Mail und schlägt eine Aufgabe vor.")
        case .filesDropped: String(localized: "Dateien werden nur bei Notizen und Rezepten übernommen.")
        }
    }
}
