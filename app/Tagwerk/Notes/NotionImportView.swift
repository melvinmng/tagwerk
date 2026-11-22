import SwiftUI
import TagwerkCore

/// Settings → Notizen → "Aus Notion importieren": pick the unpacked export folder, look at the preview, import.
struct NotionImportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: NotionImportModel?
    @State private var isPicking = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Aus Notion importieren")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model == nil { model = NotionImportModel(store: environment.notes, calendar: environment.planning.calendar) }
        }
    }

    private func content(_ model: NotionImportModel) -> some View {
        List {
            switch model.phase {
            case .idle:
                instructions(model)
            case .reading:
                Section { HStack { ProgressView(); Text("Export wird gelesen …").padding(.leading, 8) } }
            case .preview(let preview):
                previewSections(preview, model: model)
            case .done(let summary):
                doneSection(summary, model: model)
            case .failed(let message):
                Section { Text(message).foregroundStyle(.redText) }
                instructions(model)
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await model.load(folder: url) } }
        }
    }

    // MARK: Sections

    private func instructions(_ model: NotionImportModel) -> some View {
        Group {
            Section {
                @Bindable var model = model
                Picker("Importieren", selection: $model.target) {
                    Text("Tagebuch mit Gott").tag(NotionImportTarget.journal)
                    Text("Bible Study").tag(NotionImportTarget.bibleStudy)
                }
                .pickerStyle(.segmented)
                Button { isPicking = true } label: { Label("Export-Ordner wählen", systemImage: "folder") }
            } footer: {
                Text("Exportiere in Notion mit „Markdown & CSV“, entpacke die Datei in der Dateien-App (Tipp auf die ZIP-Datei) und wähle dann den entpackten Ordner. Eine ZIP-Datei liest Tagwerk nicht selbst.")
            }
            Section {
                Group {
                    if model.target == .journal {
                        Text("Importiert werden die Seiten, die in Notion zu „Tagebuch mit Gott“ gehören. Der Text bleibt auf deinem iPhone.")
                    } else {
                        Text("Importiert werden die Seiten, die in Notion zu „Bible Studies“ gehören, je Bibelbuch eine Notiz. Sitzungen lassen sich daraus nicht ableiten. Der Text bleibt auf deinem iPhone.")
                    }
                }
                .font(.footnote).foregroundStyle(.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: NotionImportModel.Preview, model: NotionImportModel) -> some View {
        let counts = preview.counts
        Section("Vorschau") {
            LabeledContent(preview.isBibleStudy ? String(localized: "Seiten im Export") : String(localized: "Einträge im Export"), value: "\(preview.foundCount)")
            if let first = preview.firstDay, let last = preview.lastDay {
                LabeledContent("Zeitraum", value: Self.period(first, last, calendar: environment.planning.calendar))
            }
            LabeledContent("Neu", value: "\(counts.newCount)")
            if counts.conflictCount > 0 {
                LabeledContent(preview.isBibleStudy ? String(localized: "Buch hat schon eine Notiz") : String(localized: "Tag hat schon einen Eintrag"),
                               value: "\(counts.conflictCount)")
            }
            if counts.alreadyImportedCount > 0 {
                LabeledContent("Schon importiert", value: "\(counts.alreadyImportedCount)")
            }
        }
        if counts.conflictCount > 0 {
            Section {
                EmptyView()
            } footer: {
                Text("Gibt es dafür schon einen Text, wird der importierte Text darunter angehängt, hinter einer Trennlinie. Nichts wird überschrieben.")
            }
        }
        if !preview.leftOutTitles.isEmpty {
            Section {
                ForEach(preview.leftOutTitles, id: \.self) { Text($0) }
            } header: {
                Text(preview.isBibleStudy ? String(localized: "Kein Bibelbuch, nicht importiert") : String(localized: "Ohne erkennbares Datum, nicht importiert"))
            }
        }
        Section {
            Button("Importieren") { model.runImport() }
                .disabled(counts.newCount + counts.conflictCount == 0)
            Button("Anderen Ordner wählen") { isPicking = true }
        }
    }

    private func doneSection(_ summary: NotionImportModel.Summary, model: NotionImportModel) -> some View {
        Section {
            Label(Self.summary(summary), systemImage: "checkmark.circle").foregroundStyle(.greenText)
            Button("Weiteren Export importieren") { model.reset() }
        }
    }

    // MARK: Texts

    static func period(_ first: PlanDay, _ last: PlanDay, calendar: Calendar) -> String {
        let style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        let from = first.startDate(in: calendar).formatted(style)
        let to = last.startDate(in: calendar).formatted(style)
        return first == last ? from : "\(from) – \(to)"
    }

    static func summary(_ result: NotionImportModel.Summary) -> String {
        var parts = [String(localized: "\(result.created) neu")]
        if result.appended > 0 { parts.append(String(localized: "\(result.appended) angehängt")) }
        if result.skipped > 0 { parts.append(String(localized: "\(result.skipped) übersprungen")) }
        return String(localized: "Import abgeschlossen:") + " " + parts.joined(separator: ", ")
    }
}
