import SwiftUI

/// The rows of the comparison before a restore (DS4b): what this iPhone holds and what the file holds. Pure, so the rule "a file
/// without journal and Bible Study leaves them alone" is tested without a view.
enum RestoreComparison {
    struct Row: Equatable {
        let title: String
        let device: Int
        /// `nil`: the file does not touch this row, it stays as it is ("bleibt erhalten").
        let file: Int?
    }

    static func rows(device: BackupService.Counts, inspection: BackupService.Inspection) -> [Row] {
        let file = inspection.counts
        return [
            Row(title: String(localized: "Aufgaben"), device: device.tasks, file: file.tasks),
            Row(title: String(localized: "Notizen"), device: device.notes, file: file.notes),
            Row(title: String(localized: "Gewohnheiten"), device: device.habits, file: file.habits),
            Row(title: String(localized: "Mahlzeiten"), device: device.meals, file: file.meals),
            Row(title: String(localized: "Tagebuch, Bible Study"), device: device.privateNotes,
                file: inspection.header.includesPrivateNotes ? file.privateNotes : nil),
        ]
    }

    /// The moment the file was written; `nil` when the header holds no readable date.
    static func createdAt(_ inspection: BackupService.Inspection) -> Date? {
        ISO8601DateFormatter().date(from: inspection.header.createdAt)
    }
}

/// The sheet that opens after a file was chosen: shows both states side by side before anything is replaced. Replacing is the only
/// way; merging is not built. The copy of the current state and the restore itself stay with the caller.
struct RestoreComparisonSheet: View {
    let inspection: BackupService.Inspection
    let device: BackupService.Counts
    let onReplace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(headline).font(.headline)
                    Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            Text("Dieses iPhone").font(.footnote.weight(.semibold)).foregroundStyle(.secondaryText)
                            Text("Sicherung").font(.footnote.weight(.semibold)).foregroundStyle(.secondaryText)
                        }
                        ForEach(RestoreComparison.rows(device: device, inspection: inspection), id: \.title) { row in
                            GridRow {
                                Text(row.title).gridColumnAlignment(.leading)
                                Text("\(row.device)").monospacedDigit()
                                if let file = row.file {
                                    Text("\(file)").monospacedDigit()
                                } else {
                                    Text("bleibt erhalten").font(.footnote).foregroundStyle(.secondaryText)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alles auf diesem iPhone wird ersetzt.").font(.subheadline.weight(.semibold))
                        Text(addedLater).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    Button(role: .destructive, action: onReplace) {
                        Text("Daten ersetzen").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("restore.replace")
                    Text("Nicht betroffen: Chatverlauf, Anmeldung bei ChatGPT und GitHub.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .navigationTitle("Wiederherstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) }
            }
        }
    }

    private var headline: String {
        guard let date = RestoreComparison.createdAt(inspection) else { return String(localized: "Sicherung") }
        return String(localized: "Sicherung vom \(date.formatted(date: .abbreviated, time: .shortened))")
    }

    private var addedLater: String {
        let date = RestoreComparison.createdAt(inspection).map { $0.formatted(date: .abbreviated, time: .omitted) }
            ?? inspection.header.createdAt
        return String(localized: "Was seit dem \(date) dazugekommen ist, steht danach nur noch in der Sicherheitskopie, die Tagwerk jetzt anlegt.")
    }
}
