import SwiftUI
import TagwerkCore

/// The guided weekly planning (#164): five steps with "Weiter" and "Zurück", every step optional. The reflection of the
/// reviewed week is saved when the step changes and when the sheet closes; nothing is sent from here.
struct WeekPlanningSheet: View {
    @State private var model: WeekPlanningModel
    @Environment(AppEnvironment.self) private var environment

    init(model: WeekPlanningModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.stepText(number: model.stepNumber, count: model.stepCount))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ProgressView(value: Double(model.stepNumber), total: Double(model.stepCount))
                    }
                    .accessibilityElement(children: .combine)
                }
                switch model.step {
                case .review: reviewSteps
                case .reflection: WeekReflectionFields(reflection: Bindable(model.weekReview).reflection)
                case .deadlines: deadlineSteps
                case .plan: planSteps
                case .habits: habitSteps
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Wochenplanung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { close() } }
            }
            .safeAreaInset(edge: .bottom) { navigation }
            .task { await model.load() }
            // Swiping the sheet away saves what was typed.
            .onDisappear { model.close() }
        }
    }

    private var navigation: some View {
        HStack {
            if !model.isFirstStep {
                Button("Zurück") { model.back() }.buttonStyle(.bordered)
            }
            Spacer()
            if model.isLastStep {
                Button("Fertig") { close() }.buttonStyle(.borderedProminent)
            } else {
                Button("Weiter") { model.next() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }

    private func close() {
        model.close()
        environment.routines.closeSheet()
    }

    // MARK: 1 Review

    @ViewBuilder
    private var reviewSteps: some View {
        let review = model.weekReview
        Section {
            if let result = review.review {
                if result.isEmpty { Text("In dieser Woche wurde nichts erfasst.").foregroundStyle(.secondary) }
                Text("\(result.completedTasks) Aufgaben")
                Text(IntakeFormat.weekTraining(minutes: result.workoutMinutes, count: result.workoutCount,
                                               goal: result.goals.workoutMinutesPerWeek))
                Text(WeekReviewView.waterText(result))
            } else {
                ProgressView()
            }
            ForEach(review.habitSummaries) { summary in
                HStack {
                    Label(summary.habit.name, systemImage: summary.habit.symbol)
                    Spacer()
                    Text(WeekReflectionSections.countText(summary)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Rückblick · \(review.title)")
        } footer: {
            Text("Hier wird nur gelesen. Nichts davon verlässt dein iPhone.")
        }
        Section {
            Button {
                close()
                environment.router.open(.review)
            } label: {
                HStack {
                    Text("Ganzen Wochenrückblick öffnen")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
    }

    // MARK: 3 Deadlines

    @ViewBuilder
    private var deadlineSteps: some View {
        Section {
            if model.deadlineTasks.isEmpty && model.deadlineEvents.isEmpty {
                Text("Keine Fälligkeiten in der neuen Woche.").foregroundStyle(.secondary)
            }
            ForEach(model.deadlineTasks) { task in
                HStack {
                    Text(task.title).lineLimit(2)
                    Spacer()
                    if let due = task.due {
                        Text(Self.dayText(PlanDay(due), calendar: model.calendar)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(model.deadlineEvents) { event in
                HStack {
                    Label(event.title, systemImage: "flag.fill").lineLimit(2)
                    Spacer()
                    Text(Self.dayText(event.day, calendar: model.calendar)).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Fälligkeiten der neuen Woche")
        } footer: {
            Text("Aufgaben mit Fälligkeit in dieser Woche oder früher, dazu die Deadlines aus deinen Kalendern.")
        }
    }

    // MARK: 4 Plan

    @ViewBuilder
    private var planSteps: some View {
        Section {
            Button {
                openPlanWeek()
            } label: {
                HStack {
                    Label("KI-Wochenplan erstellen", systemImage: "sparkles")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            Button {
                openPlanWeek()
            } label: {
                HStack {
                    Label("Selbst planen", systemImage: "calendar")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        } header: {
            Text("Woche planen")
        } footer: {
            Text("Beides öffnet „Planen“ in der Woche, die du planst. Den KI-Plan startest du dort mit dem KI-Knopf; von hier wird nichts gesendet.")
        }
    }

    private func openPlanWeek() {
        model.openPlanWeek()
        environment.routines.closeSheet()
    }

    // MARK: 5 Habits and appointments

    @ViewBuilder
    private var habitSteps: some View {
        Section {
            WeekPlanningChecklist(reflection: Bindable(model.weekReview).reflection)
        } header: {
            Text("Neue Woche planen")
        }
        let habits = environment.habits.habits.filter { $0.pausedSince == nil }
        Section {
            if habits.isEmpty { Text("Keine aktive Gewohnheit.").foregroundStyle(.secondary) }
            ForEach(habits) { habit in Label(habit.name, systemImage: habit.symbol) }
            NavigationLink("Gewohnheiten bearbeiten") { HabitListView(model: environment.habits) }
        } header: {
            Text("Gewohnheiten")
        }
    }

    // MARK: Texts

    /// "Schritt 2 von 5".
    static func stepText(number: Int, count: Int) -> String {
        String(localized: "Schritt \(number) von \(count)")
    }

    /// "Mo. 23.11."
    static func dayText(_ day: PlanDay, calendar: Calendar) -> String {
        DateText.shortWeekday(day, calendar: calendar) + " " + DateText.numericDay(day, calendar: calendar)
    }
}
