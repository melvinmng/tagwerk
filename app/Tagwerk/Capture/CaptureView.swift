import HealthBridge
import SwiftUI
import TagwerkCore

/// The "Erfassen" tab (mockup E1a): the day against the goals, quick entry, and the entries grouped by kind.
struct CaptureView: View {
    @Bindable var model: CaptureModel
    @Environment(AppEnvironment.self) private var environment
    @State private var sheet: CaptureSheet?
    @State private var showsReview = false

    enum CaptureSheet: Identifiable {
        case newMeal(text: String? = nil)
        case meal(MealValue)
        case drinks
        case newWorkout(activity: WorkoutActivity? = nil, minutes: Int? = nil)
        case workout(WorkoutValue)

        var id: String {
            switch self {
            case .newMeal: "newMeal"
            case .meal(let meal): "meal-\(meal.id)"
            case .drinks: "drinks"
            case .newWorkout: "newWorkout"
            case .workout(let workout): "workout-\(workout.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayNavigation(model: model)
                    DaySummary(model: model)
                }
                Section {
                    quickEntry
                } footer: {
                    if !model.hasEntries {
                        Text(model.isToday ? "Noch nichts erfasst. Tippe oben auf Essen, Trinken oder Training."
                                           : "An diesem Tag ist nichts erfasst.")
                    }
                }
                if model.showsHealthCard {
                    Section { HealthCard(model: model) }
                }
                mealSection
                drinkSection
                workoutSection
            }
            .navigationTitle("Erfassen")
            .assistantToolbarButton { .capture }
            .safeAreaInset(edge: .bottom) {
                if let notice = model.undo {
                    let isDeletion = if case .restore = notice.action { true } else { false }
                    UndoCapsule(title: notice.text, caption: isDeletion ? "Gelöscht" : "Erfasst",
                                symbol: isDeletion ? "trash.circle.fill" : "checkmark.circle.fill",
                                duration: HealthMirror.undoWindow,
                                onUndo: { Task { await model.undoLast() } },
                                onExpire: { model.clearUndo(notice) })
                        .id(notice.id)
                }
            }
            .task {
                await model.reload()
                // Catch up on entries that could not reach Health before (design §4.2).
                await model.syncPending()
            }
            .refreshable { await model.reload() }
            .onAppear(perform: applyPrefill)
            .onChange(of: environment.router.capturePrefill) { _, _ in applyPrefill() }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .newMeal(let text):
                    MealSheet(model: model, estimator: environment.mealEstimator, existing: nil, initialText: text)
                case .meal(let meal): MealSheet(model: model, estimator: environment.mealEstimator, existing: meal)
                case .drinks: DrinkSheet(model: model)
                case .newWorkout(let activity, let minutes):
                    WorkoutSheet(model: model, existing: nil, initialActivity: activity, initialMinutes: minutes)
                case .workout(let workout): WorkoutSheet(model: model, existing: workout)
                }
            }
        }
    }

    /// A link or shortcut asked for a sheet: entries from Siri belong to now, so the tab returns to today first.
    private func applyPrefill() {
        guard let prefill = environment.router.takeCapturePrefill() else { return }
        Task {
            if prefill != .review { await model.goToToday() }
            switch prefill {
            case .meal(let text): sheet = .newMeal(text: text)
            case .workout(let activity, let minutes): sheet = .newWorkout(activity: activity, minutes: minutes)
            case .review: showsReview = true
            }
        }
    }

    // MARK: Quick entry

    private var quickEntry: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                quickButton("Essen", symbol: "fork.knife") { sheet = .newMeal() }
                quickButton("Trinken", symbol: "drop.fill") { sheet = .drinks }
                quickButton("Training", symbol: "figure.run") { sheet = .newWorkout() }
            }
            HStack(spacing: 8) {
                ForEach(DrinkValue.quickAmounts, id: \.self) { amount in
                    Button {
                        Task { await model.addWater(amount) }
                    } label: {
                        Text("+ \(amount) ml").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .accessibilityLabel("\(amount) Milliliter Wasser erfassen")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func quickButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
    }

    // MARK: Sections

    @ViewBuilder
    private var mealSection: some View {
        if !model.meals.isEmpty {
            Section {
                ForEach(model.meals) { meal in
                    Button { sheet = .meal(meal) } label: { MealRow(meal: meal, calendar: model.calendar) }
                        .tint(.primary)
                        .swipeActions { deleteButton(meal.id) }
                }
            } header: {
                HStack {
                    Text("Essen")
                    Spacer()
                    Text(IntakeFormat.kcal(model.intake.kcal, estimated: model.intake.hasEstimate))
                }
            }
        }
    }

    @ViewBuilder
    private var drinkSection: some View {
        if !model.drinks.isEmpty {
            Section("Trinken") {
                Button { sheet = .drinks } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wasser")
                            Text(drinkCaption).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(IntakeFormat.liters(model.intake.waterMilliliters)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
        }
    }

    private var drinkCaption: String {
        let count = model.drinks.count
        let last = model.drinks.last.map { " · zuletzt \(CaptureText.time($0.date, calendar: model.calendar))" } ?? ""
        return "\(count) \(count == 1 ? "Eintrag" : "Einträge")\(last)"
    }

    @ViewBuilder
    private var workoutSection: some View {
        if !model.workouts.isEmpty {
            Section {
                ForEach(model.workouts) { workout in
                    if workout.isOwn {
                        Button { sheet = .workout(workout) } label: { WorkoutRow(workout: workout, calendar: model.calendar) }
                            .tint(.primary)
                            .swipeActions {
                                if let id = UUID(uuidString: workout.id) { deleteButton(id) }
                            }
                    } else {
                        WorkoutRow(workout: workout, calendar: model.calendar)
                    }
                }
            } header: {
                Text("Training")
            } footer: {
                if model.workouts.contains(where: { !$0.isOwn }) {
                    Text("Trainings aus Health änderst oder löschst du in der App „Fitness“ oder „Health“.")
                }
            }
        }
    }

    private func deleteButton(_ id: UUID) -> some View {
        Button(role: .destructive) {
            Task { await model.delete(id) }
        } label: {
            Label("Löschen", systemImage: "trash")
        }
    }
}

// MARK: - Header

private struct DayNavigation: View {
    let model: CaptureModel

    var body: some View {
        HStack {
            Button {
                Task { await model.goBack() }
            } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .accessibilityLabel("Vorheriger Tag")
            Spacer()
            Button {
                Task { await model.goToToday() }
            } label: {
                VStack(spacing: 0) {
                    Text(CaptureText.relativeDay(model.day, today: model.today, calendar: model.calendar)).font(.headline)
                    Text(CaptureText.date(model.day, calendar: model.calendar)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            .disabled(model.isToday)
            Spacer()
            Button {
                Task { await model.goForward() }
            } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .disabled(!model.canGoForward)
            .accessibilityLabel("Nächster Tag")
        }
        .buttonStyle(.borderless)
    }
}

private struct DaySummary: View {
    let model: CaptureModel

    var body: some View {
        let settings = model.settings
        let intake = model.intake
        let remaining = IntakeFormat.remaining(goal: settings.goalKilocalories, intake: intake)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(IntakeFormat.kcalNumber(intake.kcal, estimated: intake.hasEstimate)) / \(IntakeFormat.grouped(settings.goalKilocalories)) kcal")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(remaining.text).font(.subheadline).foregroundStyle(remaining.isOver ? .orange : .secondary)
                }
                ProgressView(value: min(1, intake.kcal / Double(max(1, settings.goalKilocalories))))
                    .tint(remaining.isOver ? .orange : .green)
            }
            HStack(spacing: 16) {
                metric("Wasser", "\(IntakeFormat.liters(intake.waterMilliliters)) / \(IntakeFormat.liters(settings.goalWaterMilliliters))",
                       progress: Double(intake.waterMilliliters) / Double(max(1, settings.goalWaterMilliliters)), tint: .cyan)
                if settings.proteinGoalEnabled {
                    metric("Eiweiß", "\(IntakeFormat.grams(intake.protein, estimated: intake.hasEstimate)) / \(settings.goalProteinGrams) g"
                        .replacingOccurrences(of: " g /", with: " /"),
                           progress: intake.protein / Double(max(1, settings.goalProteinGrams)), tint: .pink)
                }
                if settings.goalWorkoutsPerWeek > 0 {
                    metric("Training", "\(model.weekCount) / \(settings.goalWorkoutsPerWeek)",
                           progress: Double(model.weekCount) / Double(settings.goalWorkoutsPerWeek), tint: .mint)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, _ value: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
            ProgressView(value: min(1, max(0, progress))).tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

struct MealRow: View {
    let meal: MealValue
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title).lineLimit(2)
                Text("\(meal.kind.germanName) · \(CaptureText.time(meal.date, calendar: calendar))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(IntakeFormat.kcal(meal.kcal, estimated: meal.hasEstimate)).monospacedDigit()
                Text(meal.hasEstimate ? IntakeFormat.shortRange(min: meal.kcalMin, max: meal.kcalMax) : "eingetragen")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutValue
    let calendar: Calendar

    var body: some View {
        HStack {
            Image(systemName: workout.activity.symbolName).foregroundStyle(.mint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.displayName)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let kilocalories = workout.kilocalories, kilocalories > 0 {
                Text("\(Int(kilocalories.rounded())) kcal").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var caption: String {
        var parts = [CaptureText.time(workout.start, calendar: calendar), "\(workout.minutes) min"]
        if let source = workout.sourceName { parts.append(source) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Health card

private struct HealthCard: View {
    let model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mit Apple Health verbinden", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.pink)
            Text("Tagwerk speichert Mahlzeiten, Wasser und Trainings zusätzlich in Health und zeigt Trainings der Apple Watch und anderer Apps. Deine Einträge bleiben auch ohne Health in Tagwerk.")
                .font(.subheadline)
            HStack {
                Button("Verbinden") { Task { await model.connectHealth() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                Button("Nicht jetzt") { model.dismissHealthCard() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Texts

enum CaptureText {
    private static let locale = Locale(identifier: "de_DE")

    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func relativeDay(_ day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        if day == today { return "Heute" }
        if day == today.adding(days: -1, calendar: calendar) { return "Gestern" }
        var style = Date.FormatStyle.dateTime.weekday(.wide).locale(locale)
        style.timeZone = calendar.timeZone
        return day.startDate(in: calendar).formatted(style)
    }

    /// "Mi., 18. Nov."
    static func date(_ day: PlanDay, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)
        style.timeZone = calendar.timeZone
        return day.startDate(in: calendar).formatted(style)
    }
}
