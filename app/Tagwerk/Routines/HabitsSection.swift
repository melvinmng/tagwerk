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
        let line = stateLine
        HStack(spacing: 12) {
            Button {
                if !row.isAutomatic { Task { await model.toggle(row.id) } }
            } label: {
                HabitStateMark(state: row.state)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: row.isFulfilled)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: row.habit.symbol).foregroundStyle(.secondaryText)
                    Text(row.habit.name)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondaryText).monospacedDigit()
                if let line { stateLineView(line) }
            }
            Spacer(minLength: 0)
            Button(action: onOpen) { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondaryText)
                .accessibilityLabel("Gewohnheit öffnen")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.habit.name)
        .accessibilityValue(accessibilityValue(subtitle: subtitle, line: line))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Gewohnheit öffnen"), onOpen)
        .accessibilityAction {
            if !row.isAutomatic { Task { await model.toggle(row.id) } }
        }
    }

    /// The line of the state; the bolt in front of it is an image, in states (3) and (4) only.
    @ViewBuilder
    private func stateLineView(_ line: String) -> some View {
        switch row.state {
        case .automaticPending, .manualDoneSourcePending:
            Label {
                Text(line).foregroundStyle(.secondaryText)
            } icon: {
                Image(systemName: "bolt.fill").foregroundStyle(HabitMarkerTint.automatic)
            }
            .font(.caption2)
        case .automaticDone, .manualOpen, .manualDone:
            Text(line).font(.caption2).foregroundStyle(.secondaryText)
        }
    }

    private var stateLine: String? {
        let workout = capture.workouts.first { $0.minutes >= IntakeRules.minimumWorkoutMinutes }
        return HabitText.stateLine(row, on: model.day, facts: model.facts, workout: workout)
    }

    private func accessibilityValue(subtitle: String, line: String?) -> String {
        [HabitText.accessibilityState(row.state), line, subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The mark in front of a row: an open circle, a progress ring, or the green check; the bolt of the automatic states sits on it.
private struct HabitStateMark: View {
    let state: HabitsModel.Row.State

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mark
            if showsBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HabitMarkerTint.automatic)
                    .padding(2)
                    .background(Circle().fill(Color(.systemBackground)))
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .manualOpen:
            Image(systemName: "circle").font(.title2).foregroundStyle(.secondaryText)
        case .manualDone, .manualDoneSourcePending, .automaticDone:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.green)
        case .automaticPending(let progress):
            if let progress {
                ZStack {
                    Circle().stroke(Color(.quaternaryLabel), lineWidth: 3)
                    Circle().trim(from: 0, to: progress)
                        .stroke(HabitMarkerTint.automatic, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
            } else {
                Image(systemName: "circle").font(.title2).foregroundStyle(.secondaryText)
            }
        }
    }

    /// The bolt sits on the check of a source that fulfilled the habit, and on the empty circle of a source without a measure; the
    /// ring needs none, it is the mark of the pending source itself.
    private var showsBolt: Bool {
        switch state {
        case .automaticDone: true
        case .automaticPending(let progress): progress == nil
        case .manualOpen, .manualDone, .manualDoneSourcePending: false
        }
    }
}
