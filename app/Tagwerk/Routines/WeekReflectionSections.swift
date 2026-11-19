import SwiftUI
import TagwerkCore

/// The three sections at the end of the weekly review (mockup GW1, design §7.9): the habits of the week, a short
/// reflection and the planning of the next week. They stay in a week without any entry. Nothing here leaves the device.
struct WeekReflectionSections: View {
    @Bindable var model: WeekReviewModel

    var body: some View {
        Section {
            if model.habitSummaries.isEmpty {
                Text("In dieser Woche war keine Gewohnheit aktiv.").foregroundStyle(.secondary)
            }
            ForEach(model.habitSummaries) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(summary.habit.name, systemImage: summary.habit.symbol)
                        Spacer()
                        Text(Self.countText(summary)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: summary.total > 0 ? min(1, Double(summary.done) / Double(summary.total)) : 0)
                        .tint(.green)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Gewohnheiten")
        }

        Section {
            TextField("Was lief gut?", text: $model.reflection.wentWell, axis: .vertical).lineLimit(2...8)
            TextField("Belastet mich etwas?", text: $model.reflection.burdens, axis: .vertical).lineLimit(2...8)
        } header: {
            Text("Reflexion")
        } footer: {
            Text("Beide Felder sind freiwillig. Die Reflexion liegt nur auf diesem iPhone.")
        }

        Section {
            Toggle("Termine eingeplant", isOn: $model.reflection.plannedAppointments)
            Toggle("Gewohnheiten eingeplant", isOn: $model.reflection.plannedHabits)
            Toggle("Aufgaben der Woche festgelegt", isOn: $model.reflection.plannedTasks)
            Button { model.planNextWeek() } label: {
                HStack {
                    Text("Woche planen")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        } header: {
            Text("Neue Woche planen")
        }
    }

    /// "3 von 4", in the running week "3 von 4 bisher".
    static func countText(_ summary: HabitWeekSummary) -> String {
        summary.isRunning ? String(localized: "\(summary.done) von \(summary.total) bisher")
                          : String(localized: "\(summary.done) von \(summary.total)")
    }
}
