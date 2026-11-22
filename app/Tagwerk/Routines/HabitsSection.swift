import SwiftUI
import TagwerkCore

/// The "Gewohnheiten" section of "Erfassen" (design §7.1): rows for the shown day, "Bearbeiten" in the header.
struct HabitsSection: View {
    let model: HabitsModel
    let capture: CaptureModel
    /// The day of the page this section belongs to (the shown day or a neighbour while it is dragged in).
    let day: PlanDay
    let onEdit: () -> Void
    @State private var sheet: Habit?
    @State private var creating = false

    var body: some View {
        let rows = model.rows(for: day)
        let counter = shownCounter(rows)
        Section {
            if model.habits.isEmpty {
                Button { creating = true } label: { Label("Gewohnheit anlegen", systemImage: "plus.circle") }
            } else if rows.isEmpty {
                Text("An diesem Tag ist keine Gewohnheit aktiv.").foregroundStyle(.secondaryText)
            }
            ForEach(rows) { row in
                HabitRow(row: row, model: model, capture: capture) { sheet = row.habit }
            }
        } header: {
            // The sheets hang on this one view: on the section they would apply to every row.
            HStack {
                Text(HabitText.header(counter))
                Spacer()
                if !model.habits.isEmpty { Button("Bearbeiten", action: onEdit).textCase(nil) }
            }
            .sheet(item: $sheet) { habit in HabitSheet(model: model, habit: habit) }
            .sheet(isPresented: $creating) { HabitSheet(model: model, habit: nil) }
        }
    }

    /// "3 von 5" for the shown day; nothing without a row.
    private func shownCounter(_ rows: [HabitsModel.Row]) -> HabitCounter? {
        rows.isEmpty ? nil : HabitCounter(done: rows.filter(\.isFulfilled).count, total: rows.count)
    }
}

private struct HabitRow: View {
    let row: HabitsModel.Row
    let model: HabitsModel
    let capture: CaptureModel
    let onOpen: () -> Void

    var body: some View {
        let subtitle = HabitText.subtitle(row.habit, today: model.today, facts: model.facts, calendar: model.calendar)
        let detail = row.isAutomatic ? sourceDetail : nil
        HStack(spacing: 12) {
            Button {
                if !row.isAutomatic { Task { await model.toggle(row.id) } }
            } label: {
                Image(systemName: row.isFulfilled ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(row.isFulfilled ? Color.green : Color.secondaryText)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: row.isFulfilled)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: row.habit.symbol).foregroundStyle(.secondaryText)
                    Text(row.habit.name)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondaryText).monospacedDigit()
                if let detail {
                    Label(detail, systemImage: "bolt.badge.automatic").font(.caption2).foregroundStyle(.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Button(action: onOpen) { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondaryText)
                .accessibilityLabel("Gewohnheit öffnen")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.habit.name)
        .accessibilityValue(accessibilityValue(subtitle: subtitle, detail: detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Gewohnheit öffnen"), onOpen)
        .accessibilityAction {
            if !row.isAutomatic { Task { await model.toggle(row.id) } }
        }
    }

    /// "automatisch · 2,1 l von 2,0 l".
    private var sourceDetail: String {
        let workout = capture.workouts.first { $0.minutes >= IntakeRules.minimumWorkoutMinutes }
        let text = HabitText.sourceDetail(row.habit, on: model.day, facts: model.facts, workout: workout)
        let marker = String(localized: "automatisch")
        return text.map { "\(marker) · \($0)" } ?? marker
    }

    private func accessibilityValue(subtitle: String, detail: String?) -> String {
        let state = row.isFulfilled ? String(localized: "erledigt") : String(localized: "offen")
        return [state, detail, subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}
