import SwiftUI
import TagwerkCore

/// The weekly review (mockup R1a, R2a; provisional): calories per day with a goal line, water, training,
/// protein with an active goal and completed tasks.
struct WeekReviewView: View {
    @State var model: WeekReviewModel
    @State private var picking = false

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
                    Text(waterText(review))
                } header: { header("Wasser", review) }
                Section {
                    Text(trainingText(review))
                } header: { header("Training", review) }
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
        }
        .navigationTitle("Wochenrückblick")
        .navigationBarTitleDisplayMode(.inline)
        .pageSwipe(excludesLeadingEdge: true) { direction in
            Task { direction == .back ? await model.goBack() : await model.goForward() }
        }
        .animation(.snappy, value: model.review)
        .sensoryFeedback(.selection, trigger: model.weekStart)
        .task { await model.reload() }
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
            CalorieBars(review: review, calendar: model.calendar)
                .frame(height: 140)
                .padding(.vertical, 4)
        } header: { header("Kalorien", review) }
    }

    private func waterText(_ review: WeekReview) -> String {
        guard let average = review.averageWaterMilliliters else { return String(localized: "Kein Wasser erfasst") }
        let days = review.days.filter { !$0.isFuture }.count
        return String(localized: "Ziel an \(review.waterGoalDays) von \(days) Tagen · Ø \(IntakeFormat.liters(average))")
    }

    private func trainingText(_ review: WeekReview) -> String {
        guard review.workoutCount > 0 else { return String(localized: "Kein Training") }
        let count = review.goals.workoutsPerWeek > 0
            ? "\(review.workoutCount) / \(review.goals.workoutsPerWeek)"
            : String(localized: "\(review.workoutCount) Trainings")
        return "\(count) · \(String(localized: "\(review.workoutMinutes) min"))"
    }
}

/// Seven bars with a goal line; days without meals are dashed placeholders, never 0 (R2a).
private struct CalorieBars: View {
    let review: WeekReview
    let calendar: Calendar
    private var weekdays: [String] { DateText.shortStandaloneWeekdaySymbols(calendar: calendar) }
    private var longWeekdays: [String] { DateText.fullWeekdaySymbols(calendar: calendar) }

    var body: some View {
        let goal = Double(max(1, review.goals.kcal))
        let top = max(goal * 1.2, review.days.compactMap(\.kcal).max() ?? 0)
        GeometryReader { geometry in
            let barArea = geometry.size.height - 18
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(height: 1)
                    .offset(y: -18 - barArea * goal / top)
                    .accessibilityHidden(true)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(review.days.enumerated()), id: \.offset) { index, day in
                        VStack(spacing: 4) {
                            bar(day, height: barArea, top: top, goal: goal)
                            Text(weekdays[index]).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label(day, index: index))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bar(_ day: WeekReview.Day, height: CGFloat, top: Double, goal: Double) -> some View {
        if let kcal = day.kcal {
            RoundedRectangle(cornerRadius: 4)
                .fill(kcal > goal ? Color.orange : Color.green)
                .frame(height: max(3, height * kcal / top))
        } else if day.isFuture {
            Color.clear.frame(height: 3)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 24)
        }
    }

    private func label(_ day: WeekReview.Day, index: Int) -> String {
        let name = longWeekdays[index]
        guard let kcal = day.kcal else { return day.isFuture ? name : String(localized: "\(name), keine Mahlzeit erfasst") }
        let amount = IntakeFormat.grouped(IntakeFormat.roundedKcal(kcal))
        return day.hasEstimate ? String(localized: "\(name), etwa \(amount) Kilokalorien")
            : String(localized: "\(name), \(amount) Kilokalorien")
    }
}
