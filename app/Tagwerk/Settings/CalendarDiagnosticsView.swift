import SwiftUI
import RemindersKit
import TagwerkCore

/// Why events of a calendar do or do not appear in "Planen" (next 7 days).
struct CalendarDiagnosticsView: View {
    let model: PlanningModel
    @State private var rows: [CalendarDiagnostic] = []
    #if DEBUG
    @State private var identifiers: [PlanningModel.IdentifierSample] = []
    #endif

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.title).font(.headline)
                            Spacer()
                            Text(row.isRead ? "wird gelesen" : "nicht ausgewählt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(row.isRead ? Color.green : Color.orange)
                        }
                        Text(details(row)).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Termine der nächsten 7 Tage. „Zusammengefasst“: gleicher Termin wird über die Kopie aus einem anderen Kalender gezeigt.")
            }
            #if DEBUG
            identifierSection
            #endif
        }
        .navigationTitle("Kalender-Diagnose")
        .task { reloadRows() }
        .refreshable { reloadRows() }
    }

    private func reloadRows() {
        rows = model.calendarDiagnostics()
        #if DEBUG
        identifiers = model.eventIdentifierSamples()
        #endif
    }

    #if DEBUG
    /// Debug only (plan deadline-marking, Task 1): local and server identifiers of up to five events per calendar,
    /// to compare before and after a subscription refresh. Shown on screen only, never logged; no titles.
    @ViewBuilder
    private var identifierSection: some View {
        ForEach(identifiers, id: \.calendarID) { sample in
            Section(sample.calendarTitle) {
                ForEach(sample.events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.start.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold))
                        Text(verbatim: "id: \(event.id)").font(.caption2.monospaced()).textSelection(.enabled)
                        Text(verbatim: "externalID: \(event.externalID ?? "–")").font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
    }
    #endif

    private func details(_ row: CalendarDiagnostic) -> String {
        var parts = ["\(row.events) Termine", "\(row.shown) gezeigt"]
        if row.hiddenByMerge > 0 { parts.append("\(row.hiddenByMerge) zusammengefasst") }
        if row.hiddenByPlaceholderDecision > 0 { parts.append("\(row.hiddenByPlaceholderDecision) per „Zusammenfassen“ ausgeblendet") }
        if row.shownAsDeadline > 0 { parts.append("\(row.shownAsDeadline) als Deadline") }
        if row.isDeadlineCalendar { parts.append("Deadline-Kalender") }
        parts.append(kindText(row.kind))
        return parts.joined(separator: " · ")
    }

    private func kindText(_ kind: CalendarKind) -> String {
        switch kind {
        case .subscription: "Abo"
        case .birthday: "Geburtstage"
        case .local: "lokal"
        case .calDAV: "iCloud/CalDAV"
        case .exchange: "Exchange"
        case .other: "sonstiger"
        }
    }
}
