import SwiftUI
import TagwerkCore

/// The one new element above the timeline of "Planen" (mockups GA1, GF1): the morning card or today's focus.
/// It exists only in the day view of today and never shows both states.
struct RoutineCard: View {
    let model: RoutinesModel
    /// Today's plan, for the time block of a focus task; `nil` when the day view shows another range.
    let plan: DayPlan?

    var body: some View {
        switch model.card {
        case .morning(let overview):
            morning(overview)
        case .focus(let marks, let done, let total):
            focus(marks, done: done, total: total)
        case nil:
            EmptyView()
        }
    }

    private func morning(_ overview: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max.fill").foregroundStyle(.orange)
            Text(overview.isEmpty ? String(localized: "Tagesstart")
                                  : String(localized: "Tagesstart · \(overview)"))
                .font(.footnote)
                // Two lines instead of cutting the numbers off; the card stays one row of buttons high.
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Starten") { model.openStart() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button { model.dismissMorningCard() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Heute ausblenden")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .task(id: model.cardOverviewInputs) { await model.refreshCardOverview() }
    }

    private func focus(_ marks: [FocusMark], done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fokus heute · \(done) von \(total)").font(.subheadline.weight(.semibold))
                Spacer()
            }
            ForEach(marks.prefix(FocusRules.maximumMarks)) { mark in
                HStack(spacing: 10) {
                    Button { Task { await model.completeFocus(mark) } } label: {
                        Image(systemName: mark.doneAt == nil ? "circle" : "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(mark.doneAt == nil ? Color.secondary : Color.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(mark.doneAt != nil)
                    .accessibilityLabel(mark.title)
                    .accessibilityValue(mark.doneAt == nil ? String(localized: "offen") : String(localized: "erledigt"))
                    .accessibilityHint(mark.doneAt == nil ? String(localized: "Hakt die Aufgabe ab") : "")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mark.title).strikethrough(mark.doneAt != nil).foregroundStyle(mark.doneAt != nil ? .secondary : .primary)
                            .lineLimit(1)
                        if let block = blockText(mark) { Text(block).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityHidden(true)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "09:00–10:30" of the task's time block today, if the plan shows one.
    private func blockText(_ mark: FocusMark) -> String? {
        guard let plan, let id = mark.taskID,
              let event = plan.blocks.first(where: { plan.links[$0.id] == id }) else { return nil }
        let calendar = model.calendar
        return "\(DateText.time(event.start, calendar: calendar))–\(DateText.time(event.end, calendar: calendar))"
    }
}
