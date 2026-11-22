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
                        StepBar(number: model.stepNumber, count: model.stepCount)
                        Text(model.stepTitle).font(.title2.weight(.bold))
                        Text(Self.stepSubtitle(number: model.stepNumber, count: model.stepCount, next: model.nextStepTitle))
                            .font(.subheadline).foregroundStyle(.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Self.stepText(number: model.stepNumber, count: model.stepCount))
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
                Button("Fertig") { finish() }.buttonStyle(.borderedProminent)
            } else {
                // Every step is optional: skipping goes on without saving what the step asked for.
                Button("Überspringen") { model.skip() }.buttonStyle(.bordered)
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

    /// "Fertig": the planning is done, so the card "Wochenplanung" in "Planen" stays away for today (RO15b).
    private func finish() {
        environment.routines.hideWeekPlanningCardToday()
        close()
    }

    // MARK: 1 Review

    @ViewBuilder
    private var reviewSteps: some View {
        let review = model.weekReview
        Section {
            if let result = review.review {
                if result.isEmpty { Text("In dieser Woche wurde nichts erfasst.").foregroundStyle(.secondaryText) }
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
                    Text(WeekReflectionSections.countText(summary)).monospacedDigit().foregroundStyle(.secondaryText)
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
                Text("Keine Fälligkeiten in der neuen Woche.").foregroundStyle(.secondaryText)
            }
            ForEach(model.deadlineTasks) { task in
                HStack {
                    Text(task.title).lineLimit(2)
                    Spacer()
                    if let due = task.due {
                        Text(Self.dayText(PlanDay(due), calendar: model.calendar)).font(.caption).foregroundStyle(.secondaryText)
                    }
                }
            }
            ForEach(model.deadlineEvents) { event in
                HStack {
                    Label(event.title, systemImage: "flag.fill").lineLimit(2)
                    Spacer()
                    Text(Self.dayText(event.day, calendar: model.calendar)).font(.caption).foregroundStyle(.secondaryText)
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
            if habits.isEmpty { Text("Keine aktive Gewohnheit.").foregroundStyle(.secondaryText) }
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

    /// "Schritt 2 von 5 · danach: Fälligkeiten der neuen Woche"; on the last step only "Schritt 5 von 5".
    static func stepSubtitle(number: Int, count: Int, next: String?) -> String {
        guard let next else { return stepText(number: number, count: count) }
        return String(localized: "Schritt \(number) von \(count) · danach: \(next)")
    }

    /// "Mo. 23.11."
    static func dayText(_ day: PlanDay, calendar: Calendar) -> String {
        DateText.shortWeekday(day, calendar: calendar) + " " + DateText.numericDay(day, calendar: calendar)
    }
}

/// Five segments, one per step: the steps up to the current one are filled (RO12b). Decoration; the value is on the heading.
private struct StepBar: View {
    let number: Int
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(1, count), id: \.self) { index in
                Capsule().fill(index <= number ? Color.accentColor : Color(.systemFill)).frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
