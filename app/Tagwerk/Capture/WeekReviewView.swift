import SwiftUI
import TagwerkCore

/// The weekly review (mockup R1a, R2a, ST1; provisional): calories per day with a goal line and the days within budget, the weight
/// figures of the week, the macros and further nutrients against the goals, water, training time, steps per day with a goal line
/// and completed tasks.
struct WeekReviewView: View {
    @State var model: WeekReviewModel
    @Environment(AppEnvironment.self) private var environment
    @State private var picking = false
    @State private var pendingSave: Task<Void, Never>?

    var body: some View {
        PagedContainer(canGoBack: true, canGoForward: model.canGoForward, isLocked: false, excludesLeadingEdge: true,
                       onPage: { direction in Task { direction == .back ? await model.goBack() : await model.goForward() } },
                       onBlockedEdge: {}) { slot in
            switch slot {
            case .current: reviewList
            case .previous, .arrived: WeekReviewPagePreview(model: model, weekStart: model.weekStart.adding(days: -7, calendar: model.calendar))
            case .next: WeekReviewPagePreview(model: model, weekStart: model.weekStart.adding(days: 7, calendar: model.calendar))
            }
        }
        .navigationTitle("Wochenrückblick")
        .navigationBarTitleDisplayMode(.inline)
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

    private var reviewList: some View {
        List {
            Section {
                header
            }
            if let review = model.review {
                if model.isWeekEmpty {
                    Section { Text("In dieser Woche wurde nichts erfasst.").foregroundStyle(.secondaryText) }
                }
                caloriesSection(review)
                weightSection(review)
                nutrientsSection(review)
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
                Section {
                    Text("\(review.completedTasks) Aufgaben")
                } header: { header("Erledigt", review) } footer: {
                    Text(WeekReviewModel.completedFooter(model.gitHub)).foregroundStyle(.secondaryText)
                }
            }
            GoalPlanningEntries(offer: .reviewOnly,
                                note: model.goalAge.map { IntakeFormat.goalsSince($0, calendar: model.calendar) })
            EffortReviewSection(model: model)
            // Phase 7: also in a week without any entry.
            WeekReflectionSections(model: model)
        }
        .scrollDismissesKeyboard(.interactively)
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
        // The tone of the other section headers, so the contrast audit has nothing to report.
        .foregroundStyle(.secondaryText)
    }

    private func dayCount(_ count: Int) -> String { String(localized: "\(count) Tagen") }

    @ViewBuilder
    private func caloriesSection(_ review: WeekReview) -> some View {
        Section {
            if review.daysWithMeals == 0 {
                Text("Keine Mahlzeiten erfasst").foregroundStyle(.secondaryText)
            } else if let average = review.averageKcal {
                Text("Ø \(IntakeFormat.kcalNumber(average, estimated: review.hasEstimate)) kcal an \(dayCount(review.daysWithMeals))")
                Text(IntakeFormat.weekBudgetDays(within: review.daysWithinBudget, of: review.daysWithMeals))
                if let budget = review.averageBudgetKcal {
                    Text(IntakeFormat.weekBudgetAverage(budget)).foregroundStyle(.secondaryText)
                }
            }
            // Each day is measured against its own budget: the plan that held on it plus the activity it credited.
            GoalBars(days: review.days, values: review.days.map(\.kcal), goals: review.days.map { Double($0.goalKcal) },
                     calendar: model.calendar,
                     color: { index, value in value > Double(review.days[index].goalKcal) ? .orange : .green },
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
        } header: { header("Kalorien", review) } footer: {
            Text("Das Ziel jedes Tages ist sein Grundziel plus die angerechnete Aktivität; die Striche zeigen es je Tag.").foregroundStyle(.secondaryText)
        }
    }

    /// The macros and the further nutrients that are switched on in one group: the mean over the days that know the value, against
    /// the goal where the goals of the week have one (decision OR4b). Carbohydrate and fat goals are the mean of the daily goals,
    /// which grow with the credited activity.
    @ViewBuilder
    private func nutrientsSection(_ review: WeekReview) -> some View {
        let nutrients = model.settings.visibleNutrients
        let hasMacros = review.proteinDays + review.carbsDays + review.fatDays > 0
        if hasMacros || nutrients.contains(where: { (review.nutrientDays[$0] ?? 0) > 0 }) {
            Section {
                macroRow("Eiweiß", mean: review.averageProtein, days: review.proteinDays, goal: review.goals.proteinGrams, review: review)
                macroRow("Kohlenhydrate", mean: review.averageCarbs, days: review.carbsDays, goal: review.averageGoalCarbs, review: review)
                macroRow("Fett", mean: review.averageFat, days: review.fatDays, goal: review.averageGoalFat, review: review)
                ForEach(nutrients, id: \.self) { nutrient in
                    LabeledContent(nutrient.displayName) {
                        Text(Self.nutrientText(nutrient, review: review)).monospacedDigit()
                    }
                }
            } header: { header("Nährwerte", review) } footer: {
                Text("Tagesmittel aus den Tagen, an denen der Wert bekannt ist. Mahlzeiten ohne Angabe fehlen in der Summe, das Mittel liegt dann eher zu niedrig.").foregroundStyle(.secondaryText)
            }
        }
    }

    private func macroRow(_ title: LocalizedStringKey, mean: Double?, days: Int, goal: Int?, review: WeekReview) -> some View {
        LabeledContent(title) {
            Text(IntakeFormat.weekMacro(mean: mean, days: days, goal: goal, estimated: review.hasEstimate)).monospacedDigit()
        }
    }

    /// "Ø 22 / 30 g an 3 Tagen", or "–" when no day knows the value (never 0).
    static func nutrientText(_ nutrient: Nutrient, review: WeekReview) -> String {
        let goal: Int? = switch nutrient {
        case .fiber: review.goals.fiberGrams
        case .sugar: review.goals.sugarLimitGrams
        case .saturatedFat, .salt: nil
        }
        return IntakeFormat.weekNutrient(nutrient, mean: review.averageNutrients[nutrient], days: review.nutrientDays[nutrient] ?? 0,
                                         goal: goal)
    }

    /// The weight of the week as compact figures (decision variant A): 7-day mean at the end of the week, change against the week
    /// before, the trend of four weeks and the distance to the target, with the way to "Verlauf und Ziele". A week without a
    /// measurement keeps the section with a hint. Signs are part of the text, never carried by colour alone.
    @ViewBuilder
    private func weightSection(_ review: WeekReview) -> some View {
        if let weight = model.weekWeight {
            let figures = weight.figures
            Section {
                if let mean = figures.mean {
                    LabeledContent {
                        Text(WeightFormat.kilograms(mean)).monospacedDigit().fontWeight(.semibold)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7-Tage-Mittel")
                            Text(WeightFormat.measurementsInWeek(figures.measurementCount)).font(.caption).foregroundStyle(.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let change = figures.change {
                        LabeledContent("Veränderung zur Vorwoche") { Text(WeightFormat.change(change)).monospacedDigit() }
                    }
                    LabeledContent("Trend · 4 Wochen") {
                        Text(figures.trendPerWeek.map { WeightFormat.changePerWeek($0) } ?? "–").monospacedDigit()
                    }
                } else if figures.measurementCount > 0, let latest = figures.latest, latest.day >= review.weekStart {
                    Text(WeightFormat.latestLine(latest, calendar: model.calendar))
                    Text("Für ein 7-Tage-Mittel fehlen Messungen: es braucht mindestens drei in sieben Tagen.")
                        .font(.subheadline).foregroundStyle(.secondaryText)
                } else {
                    Text("Kein Gewicht erfasst")
                        .foregroundStyle(.secondaryText)
                        .accessibilityIdentifier(AccessibilityID.WeekReview.noWeight)
                }
                if let target = weight.targetKg {
                    LabeledContent("Zielgewicht") {
                        Text(WeightFormat.targetLine(targetKg: target, remaining: figures.remainingToTarget)).monospacedDigit()
                    }
                }
                NavigationLink {
                    TrendView(model: environment.makeTrendModel(), planning: { GoalPlanningEntries() })
                } label: {
                    Text("Verlauf und Ziele öffnen")
                }
                .accessibilityIdentifier(AccessibilityID.WeekReview.trendLink)
            } header: { header("Gewicht", review) } footer: {
                Text("7-Tage-Mittel am Ende der Woche; der Trend vergleicht mit dem Stand vier Wochen davor. Eigene Einträge und, wenn erlaubt, Messungen aus Health.").foregroundStyle(.secondaryText)
            }
        }
    }

    /// ST1: mean and goal days, seven bars with a goal line; days without a value are dashed, never 0.
    private func stepsSection(_ review: WeekReview) -> some View {
        Section {
            Text(IntakeFormat.weekSteps(average: review.averageSteps, goalDays: review.stepGoalDays,
                                        elapsedDays: review.days.filter { !$0.isFuture }.count, goal: review.goals.stepsPerDay))
            GoalBars(days: review.days, values: review.days.map { $0.steps.map(Double.init) },
                     goals: review.days.map { Double($0.goalSteps) }, calendar: model.calendar,
                     color: { _, _ in .indigo },
                     label: { day, name in
                         guard let steps = day.steps else {
                             return day.isFuture ? name : String(localized: "\(name), keine Schritte")
                         }
                         return String(localized: "\(name), \(IntakeFormat.steps(steps)) Schritte")
                     })
                .frame(height: 100)
                .padding(.vertical, 4)
        } header: { header("Schritte", review) } footer: {
            Text("Schritte kommen aus Health (iPhone und Apple Watch, von Health zusammengeführt).").foregroundStyle(.secondaryText)
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
    /// The goal of each day; a goal of 0 draws no mark.
    let goals: [Double]
    let calendar: Calendar
    /// The colour of a bar, from the index of the day and its value.
    let color: (Int, Double) -> Color
    /// VoiceOver text of a day, given the full weekday name.
    let label: (WeekReview.Day, String) -> String
    private var weekdays: [String] { DateText.shortStandaloneWeekdaySymbols(calendar: calendar) }
    private var longWeekdays: [String] { DateText.fullWeekdaySymbols(calendar: calendar) }

    var body: some View {
        let highest = values.compactMap { $0 }.max() ?? 0
        let highestGoal = goals.max() ?? 0
        let top = max(highestGoal * 1.2, highest * (highestGoal > 0 ? 1 : 1.1), 1)
        GeometryReader { geometry in
            let barArea = geometry.size.height - 18
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                bar(values[index], index: index, isFuture: day.isFuture, height: barArea, top: top)
                                    .frame(maxHeight: barArea, alignment: .bottom)
                                // The goal of this day: a mark across the bar, so a goal that changes within the week stays readable.
                                if goals[index] > 0 {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.6))
                                        .frame(height: 1)
                                        .offset(y: -barArea * min(1, goals[index] / top))
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(height: barArea, alignment: .bottom)
                            Text(weekdays[index]).font(.caption2).foregroundStyle(.secondaryText)
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
    private func bar(_ value: Double?, index: Int, isFuture: Bool, height: CGFloat, top: Double) -> some View {
        if let value {
            RoundedRectangle(cornerRadius: 4)
                .fill(color(index, value))
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
