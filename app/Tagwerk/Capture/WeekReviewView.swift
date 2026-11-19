import SwiftUI
import TagwerkCore

/// The weekly review (mockup R1a, R2a, ST1; provisional): calories per day with a goal line, water, training time,
/// steps per day with a goal line, protein with an active goal and completed tasks.
struct WeekReviewView: View {
    @State var model: WeekReviewModel
    @State private var picking = false
    @State private var pendingSave: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                header
            }
            if let review = model.review {
                if review.isEmpty {
                    Section { Text("In dieser Woche wurde nichts erfasst.").foregroundStyle(.secondary) }
                }
                caloriesSection(review)
                Section {
                    Text(Self.waterText(review))
                } header: { header("Wasser", review) }
                Section {
                    Text(IntakeFormat.weekTraining(minutes: review.workoutMinutes, count: review.workoutCount,
                                                   goal: review.goals.workoutMinutesPerWeek))
                } header: { header("Training", review) }
                if model.showsSteps {
                    stepsSection(review)
                }
                if let protein = review.averageProtein, let goal = review.goals.proteinGrams {
                    Section {
                        Text("Ø \(review.hasEstimate ? "~" : "")\(Int(protein.rounded())) g / \(goal) g an \(dayCount(review.daysWithMeals))")
                    } header: { header("Eiweiß", review) }
                }
                Section {
                    Text("\(review.completedTasks) Aufgaben")
                } header: { header("Erledigt", review) } footer: {
                    Text("Erinnerungen und lokale Aufgaben, ohne GitHub")
                }
            }
            EffortReviewSection(model: model)
            // Phase 7: also in a week without any entry.
            WeekReflectionSections(model: model)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Wochenrückblick")
        .navigationBarTitleDisplayMode(.inline)
        .pageSwipe(excludesLeadingEdge: true) { direction in
            Task { direction == .back ? await model.goBack() : await model.goForward() }
        }
        .animation(.snappy, value: model.review)
        .sensoryFeedback(.selection, trigger: model.weekStart)
        .task { await model.reload() }
        // The reflection is saved shortly after typing and when the page closes.
        .onChange(of: model.reflection) { _, _ in
            pendingSave?.cancel()
            pendingSave = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                model.saveReflection()
            }
        }
        .onDisappear {
            pendingSave?.cancel()
            model.saveReflection()
        }
    }

    /// Mockup EK1: caption "DIESE WOCHE · KW 47" above the week "16.–22. Nov." with ▾, then "Heute" and the arrows.
    private var header: some View {
        let range = model.weekStart...model.weekStart.adding(days: 6, calendar: model.calendar)
        let current = !model.canGoForward
        let caption = PlanHeaderText.caption(scope: .week, anchor: model.weekStart, today: model.today, range: range,
                                             calendar: model.calendar)
        let title = PlanHeaderText.title(scope: .week, anchor: model.weekStart, range: range, calendar: model.calendar)
        return HStack(spacing: 8) {
            Button { picking = true } label: {
                PageTitleLabel(caption: caption, title: title, isCurrent: current)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(caption.capitalized)
            .accessibilityHint("Woche wählen")
            .accessibilityAddTraits(.isHeader)
            .popover(isPresented: $picking) {
                DateJumpPopover(selected: model.weekStart, today: model.today, latest: model.today, calendar: model.calendar,
                                todayTitle: "Diese Woche") { day in
                    picking = false
                    Task { await model.go(toWeekOf: day) }
                }
            }
            Spacer(minLength: 8)
            if !current { PageTodayButton { Task { await model.go(toWeekOf: model.today) } } }
            PageArrowCapsule(backLabel: String(localized: "Vorherige Woche"), forwardLabel: String(localized: "Nächste Woche"),
                             canGoForward: model.canGoForward) { direction in
                Task { direction == .back ? await model.goBack() : await model.goForward() }
            }
        }
    }

    private func header(_ title: LocalizedStringResource, _ review: WeekReview) -> some View {
        HStack {
            Text(title)
            Spacer()
            if review.isCurrentWeek { Text("bisher") }
        }
    }

    private func dayCount(_ count: Int) -> String { String(localized: "\(count) Tagen") }

    @ViewBuilder
    private func caloriesSection(_ review: WeekReview) -> some View {
        Section {
            if review.daysWithMeals == 0 {
                Text("Keine Mahlzeiten erfasst").foregroundStyle(.secondary)
            } else if let average = review.averageKcal {
                Text("Ø \(IntakeFormat.kcalNumber(average, estimated: review.hasEstimate)) kcal an \(dayCount(review.daysWithMeals))")
            }
            let goal = Double(max(1, review.goals.kcal))
            GoalBars(days: review.days, values: review.days.map(\.kcal), goal: goal, calendar: model.calendar,
                     color: { $0 > goal ? .orange : .green },
                     label: { day, name in
                         guard let kcal = day.kcal else {
                             return day.isFuture ? name : String(localized: "\(name), keine Mahlzeit erfasst")
                         }
                         let amount = IntakeFormat.grouped(IntakeFormat.roundedKcal(kcal))
                         return day.hasEstimate ? String(localized: "\(name), etwa \(amount) Kilokalorien")
                             : String(localized: "\(name), \(amount) Kilokalorien")
                     })
                .frame(height: 140)
                .padding(.vertical, 4)
        } header: { header("Kalorien", review) }
    }

    /// ST1: mean and goal days, seven bars with a goal line; days without a value are dashed, never 0.
    private func stepsSection(_ review: WeekReview) -> some View {
        Section {
            Text(IntakeFormat.weekSteps(average: review.averageSteps, goalDays: review.stepGoalDays,
                                        elapsedDays: review.days.filter { !$0.isFuture }.count, goal: review.goals.stepsPerDay))
            GoalBars(days: review.days, values: review.days.map { $0.steps.map(Double.init) },
                     goal: Double(review.goals.stepsPerDay), calendar: model.calendar,
                     color: { _ in .indigo },
                     label: { day, name in
                         guard let steps = day.steps else {
                             return day.isFuture ? name : String(localized: "\(name), keine Schritte")
                         }
                         return String(localized: "\(name), \(IntakeFormat.steps(steps)) Schritte")
                     })
                .frame(height: 100)
                .padding(.vertical, 4)
        } header: { header("Schritte", review) } footer: {
            Text("Schritte kommen aus Health (iPhone und Apple Watch, von Health zusammengeführt).")
        }
    }

    static func waterText(_ review: WeekReview) -> String {
        guard let average = review.averageWaterMilliliters else { return String(localized: "Kein Wasser erfasst") }
        let days = review.days.filter { !$0.isFuture }.count
        return String(localized: "Ziel an \(review.waterGoalDays) von \(days) Tagen · Ø \(IntakeFormat.liters(average))")
    }
}

/// Seven bars with a goal line (R2a, ST1): one per weekday; days without a value are dashed placeholders, never 0,
/// later days stay empty. A goal of 0 draws no line.
private struct GoalBars: View {
    let days: [WeekReview.Day]
    let values: [Double?]
    let goal: Double
    let calendar: Calendar
    let color: (Double) -> Color
    /// VoiceOver text of a day, given the full weekday name.
    let label: (WeekReview.Day, String) -> String
    private var weekdays: [String] { DateText.shortStandaloneWeekdaySymbols(calendar: calendar) }
    private var longWeekdays: [String] { DateText.fullWeekdaySymbols(calendar: calendar) }

    var body: some View {
        let highest = values.compactMap { $0 }.max() ?? 0
        let top = max(goal * 1.2, highest * (goal > 0 ? 1 : 1.1), 1)
        GeometryReader { geometry in
            let barArea = geometry.size.height - 18
            ZStack(alignment: .bottomLeading) {
                if goal > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(height: 1)
                        .offset(y: -18 - barArea * goal / top)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        VStack(spacing: 4) {
                            bar(values[index], isFuture: day.isFuture, height: barArea, top: top)
                            Text(weekdays[index]).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label(day, longWeekdays[index]))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bar(_ value: Double?, isFuture: Bool, height: CGFloat, top: Double) -> some View {
        if let value {
            RoundedRectangle(cornerRadius: 4)
                .fill(color(value))
                .frame(height: max(3, height * value / top))
        } else if isFuture {
            Color.clear.frame(height: 3)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 24)
        }
    }
}
