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
                HStack {
                    Button { Task { await model.goBack() } } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Vorherige Woche")
                    Spacer()
                    Button { picking = true } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(model.title).font(.headline).monospacedDigit()
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityHint("Woche wählen")
                    .popover(isPresented: $picking) {
                        DateJumpPopover(selected: model.weekStart, today: model.today, calendar: model.calendar,
                                        todayTitle: "Diese Woche") { day in
                            picking = false
                            Task { await model.go(toWeekOf: day) }
                        }
                    }
                    Spacer()
                    Button { Task { await model.goForward() } } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canGoForward)
                        .accessibilityLabel("Nächste Woche")
                }
                .buttonStyle(.borderless)
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
        .pageSwipe(back: { await model.goBack() }, forward: { await model.goForward() })
        .sensoryFeedback(.selection, trigger: model.weekStart)
        .task { await model.reload() }
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
