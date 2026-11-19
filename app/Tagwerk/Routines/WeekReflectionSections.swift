import SwiftUI
import TagwerkCore

/// The sections at the end of the weekly review (mockup GW1, design §7.9): the habits of the week, a short
/// reflection and the planning of the next week. They stay in a week without any entry. Nothing here leaves the device.
struct WeekReflectionSections: View {
    @Bindable var model: WeekReviewModel
    @Environment(AppEnvironment.self) private var environment

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

        WeekReflectionFields(reflection: $model.reflection)

        Section {
            Button {
                // What was typed here is saved first: the sheet works on the same stored reflection.
                model.saveReflection()
                environment.routines.openWeek()
            } label: {
                HStack {
                    Text("Wochenplanung starten")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            // The planning sheet may have changed the reflection of this week: read it again when the sheet closes.
            .onChange(of: environment.routines.sheet) { _, sheet in
                if sheet == nil { Task { await model.reload() } }
            }
            WeekPlanningChecklist(reflection: $model.reflection)
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

/// The "Reflexion" section: the three questions of the original weekly template. Also used by the guided weekly planning.
struct WeekReflectionFields: View {
    @Binding var reflection: WeekReflection

    var body: some View {
        Section {
            TextField("Was lief gut?", text: $reflection.wentWell, axis: .vertical).lineLimit(2...8).keyboardDoneButton()
            TextField("Belastet mich etwas?", text: $reflection.burdens, axis: .vertical).lineLimit(2...8).keyboardDoneButton()
            TextField("Wie laufen meine Ziele, Projekte und Tasks?", text: $reflection.goalsProgress, axis: .vertical)
                .lineLimit(2...8).keyboardDoneButton()
        } header: {
            Text("Reflexion")
        } footer: {
            Text("Alle Felder sind freiwillig. Die Reflexion liegt nur auf diesem iPhone.")
        }
    }
}

/// The three checks for the next week, in the wording of the original template. These are rows for a `Section` of the
/// caller, so the guided weekly planning can show them next to its own rows.
struct WeekPlanningChecklist: View {
    @Binding var reflection: WeekReflection

    var body: some View {
        Toggle("Termine und Gewohnheiten in den Kalender eingetragen?", isOn: $reflection.calendarPlanned)
        Toggle("Projekte und Tasks der Woche eingetragen?", isOn: $reflection.tasksPlanned)
        Toggle("Kurzen Moment für Dankbarkeit genommen?", isOn: $reflection.gratitudeTaken)
    }
}
