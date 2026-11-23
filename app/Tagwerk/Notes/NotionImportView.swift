import SwiftUI
import TagwerkCore

/// The Notion import as a sheet in three steps (TB4b): 1 pick the unpacked export folder (with the instructions), 2 preview,
/// 3 result. Opened from Settings → Notizen (with the choice of journal or Bible Study) or from an empty journal or
/// Bible Study folder (the target is then fixed). The text of the files never leaves the device.
struct NotionImportView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: NotionImportModel?
    @State private var isPicking = false
    let fixedTarget: NotionImportTarget?
    /// Called after the sheet closed with "Zum Tagebuch" / "Zu Bible Study"; the presenter shows the folder.
    let onShowFolder: (NotionImportTarget) -> Void

    init(fixedTarget: NotionImportTarget? = nil, onShowFolder: @escaping (NotionImportTarget) -> Void = { _ in }) {
        self.fixedTarget = fixedTarget
        self.onShowFolder = onShowFolder
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Aus Notion importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil {
                model = NotionImportModel(store: environment.notes, calendar: environment.planning.calendar, fixedTarget: fixedTarget)
            }
        }
    }

    private func content(_ model: NotionImportModel) -> some View {
        List {
            stepHeader(model.step)
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

    // MARK: Step header

    /// Three dots and the title of the step ("1 · Export wählen").
    private func stepHeader(_ step: NotionImportModel.Step) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { number in
                        Capsule().fill(number <= step.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.systemFill)))
                            .frame(width: 28, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Text(Self.stepTitle(step)).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    // MARK: Step 1

    private func instructions(_ model: NotionImportModel) -> some View {
        Group {
            if model.showsTargetChoice {
                Section {
                    @Bindable var model = model
                    Picker("Importieren", selection: $model.target) {
                        Text("Tagebuch mit Gott").tag(NotionImportTarget.journal)
                        Text("Bible Study").tag(NotionImportTarget.bibleStudy)
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section {
                instructionRow(1, Text("Exportiere in Notion mit „Markdown & CSV“."))
                instructionRow(2, Text("Entpacke die ZIP-Datei in der Dateien-App (Tipp auf die Datei). Tagwerk liest keine ZIP-Datei selbst."))
                instructionRow(3, Text("Wähle hier den entpackten Ordner."))
            } footer: {
                Text(model.target == .journal
                     ? "Importiert werden die Seiten, die in Notion zu „Tagebuch mit Gott“ gehören. Der Text bleibt auf deinem iPhone."
                     : "Importiert werden die Seiten, die in Notion zu „Bible Studies“ gehören, je Bibelbuch eine Notiz. Sitzungen lassen sich daraus nicht ableiten. Der Text bleibt auf deinem iPhone.")
            }
            Section {
                Button { isPicking = true } label: { Label("Ordner wählen", systemImage: "folder") }
            }
        }
    }

    private func instructionRow(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.tint)
            text
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Step 2

    @ViewBuilder
    private func previewSections(_ preview: NotionImportModel.Preview, model: NotionImportModel) -> some View {
        let counts = preview.counts
        Section {
            LabeledContent(preview.isBibleStudy ? String(localized: "Seiten im Export") : String(localized: "Einträge im Export"), value: "\(preview.foundCount)")
            if let first = preview.firstDay, let last = preview.lastDay {
                LabeledContent("Zeitraum", value: Self.period(first, last, calendar: environment.planning.calendar))
            }
            LabeledContent("Neu", value: "\(counts.newCount)")
            if counts.conflictCount > 0 {
                if preview.conflicts.isEmpty {
                    LabeledContent(String(localized: "Buch hat schon eine Notiz"), value: "\(counts.conflictCount)")
                } else {
                    NavigationLink {
                        conflictList(preview.conflicts)
                    } label: {
                        LabeledContent("Tag hat schon einen Eintrag", value: "\(counts.conflictCount)")
                    }
                }
            }
            if counts.alreadyImportedCount > 0 {
                LabeledContent("Schon importiert", value: "\(counts.alreadyImportedCount)")
            }
            if !preview.leftOutTitles.isEmpty {
                NavigationLink {
                    leftOutList(preview)
                } label: {
                    LabeledContent(preview.isBibleStudy ? String(localized: "Kein Bibelbuch") : String(localized: "Ohne erkennbares Datum"),
                                   value: "\(preview.leftOutTitles.count)")
                }
            }
        } footer: {
            Text("Gibt es dafür schon einen Text, wird der importierte Text darunter angehängt, hinter einer Trennlinie. Nichts wird überschrieben.")
        }
        Section {
            Button(preview.importButtonTitle) { model.runImport() }
                .font(.body.weight(.semibold))
                .disabled(preview.importCount == 0)
            Button("Anderen Ordner wählen") { isPicking = true }
        }
    }

    /// TB5a: the days whose entry gets the imported text appended, newest first.
    private func conflictList(_ conflicts: [NotionImportModel.Preview.Conflict]) -> some View {
        let calendar = environment.planning.calendar
        return List {
            Section {
                ForEach(conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dayTitle(conflict.day, calendar: calendar))
                        Text(Self.excerptLine(conflict)).font(.footnote).foregroundStyle(.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("An diesen Tagen wird der Text aus Notion unter deinem Eintrag angehängt.").textCase(nil)
            }
        }
        .navigationTitle(Self.conflictTitle(conflicts.count))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The pages without a usable date or without a book: listed by their title, not imported.
    private func leftOutList(_ preview: NotionImportModel.Preview) -> some View {
        List {
            Section {
                ForEach(Array(preview.leftOutTitles.enumerated()), id: \.offset) { _, title in Text(title) }
            } header: {
                Text(preview.isBibleStudy ? String(localized: "Kein Bibelbuch, nicht importiert") : String(localized: "Ohne erkennbares Datum, nicht importiert"))
                    .textCase(nil)
            }
        }
        .navigationTitle(preview.isBibleStudy ? String(localized: "Kein Bibelbuch") : String(localized: "Ohne erkennbares Datum"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Step 3

    private func doneSection(_ summary: NotionImportModel.Summary, model: NotionImportModel) -> some View {
        Group {
            Section {
                Label(Self.summary(summary), systemImage: "checkmark.circle").foregroundStyle(.greenText)
            }
            Section {
                Button(model.target == .journal ? "Zum Tagebuch" : "Zu Bible Study") {
                    let target = model.target
                    dismiss()
                    onShowFolder(target)
                }
                .font(.body.weight(.semibold))
                Button("Weiteren Export importieren") { model.reset() }
            }
        }
    }

    // MARK: Texts

    static func stepTitle(_ step: NotionImportModel.Step) -> String {
        switch step {
        case .instructions: String(localized: "1 · Export wählen")
        case .preview: String(localized: "2 · Vorschau")
        case .result: String(localized: "3 · Ergebnis")
        }
    }

    static func conflictTitle(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Tag mit Eintrag") : String(localized: "\(count) Tage mit Eintrag")
    }

    /// "Tagwerk: „Müde, aber ruhig …“ · Notion: „Heute im Hauskreis …“"; an excerpt without text shows "kein Text".
    static func excerptLine(_ conflict: NotionImportModel.Preview.Conflict) -> String {
        let existing = conflict.existingExcerpt.isEmpty ? String(localized: "kein Text") : conflict.existingExcerpt
        let imported = conflict.importedExcerpt.isEmpty ? String(localized: "kein Text") : conflict.importedExcerpt
        return String(localized: "Tagwerk: „\(existing)“ · Notion: „\(imported)“")
    }

    static func dayTitle(_ day: PlanDay, calendar: Calendar) -> String {
        day.startDate(in: calendar).formatted(Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide).year())
    }

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
