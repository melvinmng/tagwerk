import HealthBridge
import SwiftUI
import TagwerkCore

/// The "Erfassen" tab (mockup E1a): the day against the goals, quick entry, and the entries grouped by kind.
struct CaptureView: View {
    @Bindable var model: CaptureModel
    @Environment(AppEnvironment.self) private var environment
    @State private var sheet: CaptureSheet?
    @State private var showsReview = false
    @State private var showsTrends = false
    @State private var showsHabitList = false
    @State private var limitBumps = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum CaptureSheet: Identifiable {
        case newMeal(text: String? = nil)
        case meal(MealValue)
        case drinks
        case newWorkout(activity: WorkoutActivity? = nil, minutes: Int? = nil)
        case workout(WorkoutValue)
        case activeBreakdown
        case foreignIntake
        case newWeight
        case weight(WeightValue)

        var id: String {
            switch self {
            case .newMeal(let text): "newMeal-\(text ?? "")"
            case .meal(let meal): "meal-\(meal.id)"
            case .drinks: "drinks"
            case .newWorkout(let activity, let minutes): "newWorkout-\(activity?.rawValue ?? "")-\(minutes ?? 0)"
            case .workout(let workout): "workout-\(workout.id)"
            case .activeBreakdown: "activeBreakdown"
            case .foreignIntake: "foreignIntake"
            case .newWeight: "newWeight"
            case .weight(let weight): "weight-\(weight.id)"
            }
        }
    }

    // Day swipe over the whole list, like "Planen" (PagedContainer); entries are deleted from their context menu
    // instead of swipe actions. Forward on today is a limit: the page springs back and `limitBumps` taps.
    private func daySwipe(_ direction: PageSwipe) {
        if !model.navigate(by: direction) { limitBumps += 1 }
    }

    var body: some View {
        NavigationStack {
            PagedContainer(canGoBack: true, canGoForward: model.canGoForward, isLocked: false,
                           onPage: daySwipe, onBlockedEdge: { limitBumps += 1 }) { slot in
                switch slot {
                case .current: dayList(model.current)
                case .previous, .arrived: preview(of: model.day.adding(days: -1, calendar: model.calendar))
                case .next: preview(of: model.day.adding(days: 1, calendar: model.calendar))
                }
            }
            .navigationTitle("Erfassen")
            .sensoryFeedback(.selection, trigger: model.day)
            // Swiping forward on today: a firm tap instead of silence (there is no later day).
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: limitBumps)
            .navigationDestination(isPresented: $showsReview) {
                WeekReviewView(model: environment.makeWeekReviewModel())
            }
            .navigationDestination(isPresented: $showsTrends) {
                TrendView(model: environment.makeTrendModel(), planning: { GoalPlanningEntries() })
            }
            .navigationDestination(isPresented: $showsHabitList) {
                HabitListView(model: environment.habits)
            }
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
                await environment.habits.reload(day: model.day)
                // Catch up on entries that could not reach Health before (design §4.2).
                await model.syncPending()
            }
            .refreshable {
                await model.reload()
                await environment.habits.reload(day: model.day)
            }
            .onChange(of: model.day) { _, day in environment.habits.show(day) }
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
                case .activeBreakdown: BudgetBreakdownSheet(model: model)
                case .foreignIntake:
                    if let foreign = model.current.figures.totals.foreign { ForeignIntakeSheet(foreign: foreign) }
                case .newWeight: WeightSheet(model: model, existing: nil)
                case .weight(let weight): WeightSheet(model: model, existing: weight)
                }
            }
        }
    }

    /// The neighbouring day beside the shown page: the same list from the day's entries and the cached Health numbers,
    /// without interaction, so the page that follows does not change when it arrives.
    private func preview(of day: PlanDay) -> some View {
        dayList(model.page(for: day), isPreview: true)
            .allowsHitTesting(false)
    }

    /// The day: summary, quick entry and the entries by kind.
    private func dayList(_ data: CaptureDay, isPreview: Bool = false) -> some View {
        List {
                Section {
                    DayNavigation(model: model, day: data.day)
                    DaySummary(model: model, data: data, onShowActive: { sheet = .activeBreakdown })
                    // R3a: entry to the weekly review (a row of its own, so VoiceOver keeps the summary as one element).
                    Button { showsReview = true } label: {
                        HStack {
                            Label("Wochenrückblick", systemImage: "chart.bar")
                            Spacer()
                            Text("Woche").foregroundStyle(.secondaryText)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    // The trends of the intake and the weight; the value is the weight of the latest 7 days, when there is one.
                    Button { showsTrends = true } label: {
                        HStack {
                            Label("Verlauf und Ziele", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            if let kilograms = model.weightOverview.mean ?? model.weightOverview.latest {
                                Text(WeightFormat.kilograms(kilograms)).monospacedDigit().foregroundStyle(.secondaryText)
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(AccessibilityID.Trend.entry)
                }
                Section {
                    quickEntry
                } footer: {
                    if !data.hasEntries {
                        Text(data.day == model.today ? "Noch nichts erfasst. Tippe oben auf Essen, Trinken oder Training."
                                                     : "An diesem Tag ist nichts erfasst.")
                    }
                }
                if model.showsHealthCard {
                    Section { HealthCard(model: model) }
                }
                RoutinesSection(model: environment.routines, day: data.day)
                HabitsSection(model: environment.habits, capture: model, day: data.day) { showsHabitList = true }
                // Below the routine cards: the card is an overview of the day, so the cards of the day stay within reach of the head.
                Section { NutrientCardView(rows: model.nutrientRows(for: data.figures)) }
                mealSection(data)
                drinkSection(data)
                workoutSection(data)
                FocusCaptureSection()
        }
        // A page opens at its top, with the large title: every day is a new list, so no scroll position carries over.
        .id(data.day)
    }

    /// A link or shortcut asked for a sheet: entries from Siri belong to now, so the tab returns to today first.
    private func applyPrefill() {
        guard let prefill = environment.router.takeCapturePrefill() else { return }
        if prefill != .review, prefill != .trends, !model.isToday {
            // The day switches at once; the sheet does not wait for the Health query of the reload.
            model.day = model.today
            Task { await model.reload() }
        }
        switch prefill {
        case .today: break
        case .meal(let text): sheet = .newMeal(text: text)
        case .workout(let activity, let minutes): sheet = .newWorkout(activity: activity, minutes: minutes)
        case .review: showsReview = true
        case .trends: showsTrends = true
        }
    }

    // MARK: Quick entry

    private var quickEntry: some View {
        VStack(spacing: 10) {
            // Four buttons in one row; with large text they wrap into two rows of two, so no label is cut off.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: QuickEntryLayout.columns(for: dynamicTypeSize)),
                      spacing: 8) {
                quickButton("Essen", symbol: "fork.knife") { sheet = .newMeal() }
                quickButton("Trinken", symbol: "drop.fill") { sheet = .drinks }
                quickButton("Training", symbol: "figure.run") { sheet = .newWorkout() }
                quickButton("Gewicht", symbol: "scalemass") { sheet = .newWeight }
                    .accessibilityIdentifier(AccessibilityID.Capture.quickWeight)
            }
            // SI3: shown once, directly above the portions; renders nothing when the shortcuts are not registered.
            if SiriTipPolicy.isVisible(done: model.settings.siriTipWaterDone) {
                SiriTip(intent: LogWaterIntent(), isDone: siriTipDone)
            }
            HStack(spacing: 8) {
                // By index: two portions may be equal, so the amount is no identity.
                ForEach(Array(model.settings.drinkPresets.enumerated()), id: \.offset) { _, amount in
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

    private var siriTipDone: Binding<Bool> {
        let settings = model.settings
        return Binding(get: { settings.siriTipWaterDone }, set: { settings.siriTipWaterDone = $0 })
    }

    private func quickButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
    }

    // MARK: Sections

    @ViewBuilder
    private func mealSection(_ data: CaptureDay) -> some View {
        let foreign = data.figures.totals.foreign
        if !data.meals.isEmpty || foreign != nil {
            Section {
                ForEach(data.meals) { meal in
                    Button { sheet = .meal(meal) } label: { MealRow(meal: meal, calendar: model.calendar) }
                        .tint(.primary)
                        .contextMenu { deleteButton(meal.id) }
                }
                // Entries of other apps: one row with the day total and the app names; it has no editor and no delete.
                if let foreign {
                    Button { sheet = .foreignIntake } label: { ForeignIntakeRow(foreign: foreign) }
                        .tint(.primary)
                }
            } header: {
                HStack {
                    Text("Essen")
                    Spacer()
                    // Everything the day counts as eaten, the entries of other apps included.
                    Text(IntakeFormat.kcal(data.figures.totals.kcal, estimated: data.figures.totals.hasEstimate))
                }
            }
        }
    }

    @ViewBuilder
    private func drinkSection(_ data: CaptureDay) -> some View {
        if !data.drinks.isEmpty {
            Section("Trinken") {
                Button { sheet = .drinks } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wasser")
                            Text(drinkCaption(data)).font(.caption).foregroundStyle(.secondaryText)
                        }
                        Spacer()
                        Text(IntakeFormat.liters(data.intake.waterMilliliters)).foregroundStyle(.secondaryText)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
        }
    }

    private func drinkCaption(_ data: CaptureDay) -> String {
        let count = data.drinks.count
        let entries = String(localized: "\(count) Einträge")
        guard let last = data.drinks.last else { return entries }
        return entries + " · " + String(localized: "zuletzt \(CaptureText.time(last.date, calendar: model.calendar))")
    }

    @ViewBuilder
    private func workoutSection(_ data: CaptureDay) -> some View {
        if !data.workouts.isEmpty {
            Section {
                ForEach(data.workouts) { workout in
                    if workout.isOwn {
                        Button { sheet = .workout(workout) } label: { WorkoutRow(workout: workout, calendar: model.calendar) }
                            .tint(.primary)
                            .contextMenu {
                                if let id = UUID(uuidString: workout.id) { deleteButton(id) }
                            }
                    } else {
                        WorkoutRow(workout: workout, calendar: model.calendar)
                    }
                }
            } header: {
                // The day's training time, like the calories in the head of "Essen" (ST1).
                HStack {
                    Text("Training")
                    Spacer()
                    Text(IntakeFormat.duration(minutes: data.dayMinutes))
                        .accessibilityLabel(IntakeFormat.spokenDuration(minutes: data.dayMinutes))
                }
            } footer: {
                if data.workouts.contains(where: { !$0.isOwn }) {
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
    /// The day of the page this header belongs to.
    let day: PlanDay
    @State private var picking = false

    /// "MI., 18. NOV. · KW 47" above the short title "Heute" / "Gestern" / "Montag" (mockup EK1).
    private var caption: String {
        let week = model.calendar.component(.weekOfYear, from: day.startDate(in: model.calendar))
        return "\(CaptureText.date(day, calendar: model.calendar)) · \(String(localized: "KW \(week)"))".uppercased()
    }

    var body: some View {
        let isToday = day == model.today
        let title = CaptureText.relativeDay(day, today: model.today, calendar: model.calendar)
        HStack(spacing: 8) {
            Button { picking = true } label: {
                PageTitleLabel(caption: caption, title: title, isCurrent: isToday)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(CaptureText.date(day, calendar: model.calendar))
            .accessibilityHint("Datum wählen")
            .accessibilityAddTraits(.isHeader)
            .popover(isPresented: $picking) {
                DateJumpPopover(selected: day, today: model.today, latest: model.today, calendar: model.calendar,
                                todayTitle: "Heute") { day in
                    picking = false
                    model.navigate(to: day)
                }
            }
            Spacer(minLength: 8)
            if !isToday { PageTodayButton { model.navigate(to: model.today) } }
            PageArrowCapsule(backLabel: String(localized: "Vorheriger Tag"), forwardLabel: String(localized: "Nächster Tag"),
                             canGoForward: model.canGoForward) { model.navigate(by: $0) }
        }
    }
}

extension CaptureModel {
    /// Changes the day at once (animatable) and adds Health in the background.
    /// Returns `false` at the limit (no day after today).
    @discardableResult
    func navigate(to target: PlanDay) -> Bool {
        guard show(target) else { return false }
        Task { await reload(refreshingLocalFirst: false) }
        return true
    }

    @discardableResult
    func navigate(by direction: PageSwipe) -> Bool {
        navigate(to: day.adding(days: direction.step, calendar: calendar))
    }
}

private struct DaySummary: View {
    let model: CaptureModel
    let data: CaptureDay
    let onShowActive: () -> Void

    var body: some View {
        let budget = data.figures.budget
        VStack(alignment: .leading, spacing: 10) {
            BudgetHead(budget: budget, offersAllow: model.offersActiveEnergy(for: budget), onShowActive: onShowActive,
                       onAllow: { Task { await model.allowActiveEnergy() } })
            // ST1: water and protein, then steps and the weekly training; single tiles share one row.
            ForEach(Array(model.summaryRows(steps: data.steps, plan: data.figures.plan).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(row, id: \.self) { tile($0) }
                }
            }
        }
        .padding(.vertical, 4)
        // Each tile is its own element, so the "In Health erlauben" button stays reachable.
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func tile(_ tile: CaptureModel.SummaryTile) -> some View {
        let plan = data.figures.plan
        let totals = data.figures.totals
        switch tile {
        case .water:
            metric("Wasser", "\(IntakeFormat.liters(totals.waterMilliliters)) / \(IntakeFormat.liters(plan.waterMilliliters))",
                   progress: Double(totals.waterMilliliters) / Double(max(1, plan.waterMilliliters)), tint: .cyan)
        case .steps:
            stepsTile
        case .training:
            let goal = plan.workoutMinutesPerWeek
            metric("Training · Woche", IntakeFormat.duration(minutes: data.weekMinutes, goal: goal),
                   progress: Double(data.weekMinutes) / Double(max(1, goal)), tint: .mint,
                   spokenLabel: String(localized: "Training diese Woche"),
                   spokenValue: String(localized: "\(IntakeFormat.spokenDuration(minutes: data.weekMinutes)) von \(IntakeFormat.spokenDuration(minutes: goal))"))
        }
    }

    @ViewBuilder
    private var stepsTile: some View {
        let goal = data.figures.plan.stepsPerDay
        switch model.stepsTile(for: data.steps) {
        case .hidden:
            EmptyView()
        case .allow:
            VStack(alignment: .leading, spacing: 3) {
                Text("Schritte").font(.caption).foregroundStyle(.secondaryText).accessibilityHidden(true)
                Button { Task { await model.allowSteps() } } label: {
                    Text("In Health erlauben \(Image(systemName: "chevron.right"))")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                // Borderless: only the button reacts, not the whole summary row.
                .buttonStyle(.borderless)
                .accessibilityLabel("Schritte in Health erlauben")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .value(let count):
            let spoken = count.map { count in
                goal > 0 ? String(localized: "\(IntakeFormat.steps(count)) von \(IntakeFormat.grouped(goal))") : IntakeFormat.steps(count)
            } ?? String(localized: "keine Daten")
            metric("Schritte", IntakeFormat.stepsValue(count, goal: goal),
                   progress: goal > 0 ? Double(count ?? 0) / Double(goal) : nil, tint: .indigo,
                   spokenLabel: String(localized: "Schritte"), spokenValue: spoken)
        }
    }

    /// One tile: caption, value and an optional bar. `spokenLabel`/`spokenValue` replace the combined reading.
    @ViewBuilder
    private func metric(_ title: LocalizedStringResource, _ value: String, progress: Double?, tint: Color,
                        spokenLabel: String? = nil, spokenValue: String? = nil) -> some View {
        let tile = VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondaryText)
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let progress {
                ProgressView(value: min(1, max(0, progress))).tint(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let spokenLabel, let spokenValue {
            tile.accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityValue(spokenValue)
        } else {
            tile.accessibilityElement(children: .combine)
        }
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
                Text("\(meal.kind.displayName) · \(CaptureText.time(meal.date, calendar: calendar))")
                    .font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(IntakeFormat.kcal(meal.kcal, estimated: meal.hasEstimate)).monospacedDigit()
                Text(meal.hasEstimate ? IntakeFormat.shortRange(min: meal.kcalMin, max: meal.kcalMax) : String(localized: "eingetragen"))
                    .font(.caption).foregroundStyle(.secondaryText)
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
                Text(caption).font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
            if let kilocalories = workout.kilocalories, kilocalories > 0 {
                Text("\(Int(kilocalories.rounded())) kcal").monospacedDigit().foregroundStyle(.secondaryText)
            }
        }
    }

    private var caption: String {
        var parts = [CaptureText.time(workout.start, calendar: calendar), IntakeFormat.duration(minutes: workout.minutes)]
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
            Text("Tagwerk speichert Mahlzeiten, Wasser und Trainings zusätzlich in Health und zeigt deine Schritte sowie Trainings der Apple Watch und anderer Apps. Deine Einträge bleiben auch ohne Health in Tagwerk.")
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

// MARK: - Quick entry layout

enum QuickEntryLayout {
    /// Buttons per row of the quick entry: all four in one row up to the default text sizes, two per row from "extra large" on.
    static func columns(for size: DynamicTypeSize) -> Int { size >= .xLarge ? 2 : 4 }
}

// MARK: - Texts

enum CaptureText {
    static func time(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        DateText.time(date, calendar: calendar, locale: locale)
    }

    static func relativeDay(_ day: PlanDay, today: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        if day == today { return String(localized: "Heute") }
        if day == today.adding(days: -1, calendar: calendar) { return String(localized: "Gestern") }
        var style = Date.FormatStyle.dateTime.weekday(.wide).locale(locale)
        style.timeZone = calendar.timeZone
        return day.startDate(in: calendar).formatted(style)
    }

    /// The day inside a sentence ("zuletzt heute"): relative words in lower case, weekday names as the language writes them.
    static func lastUsedDay(_ day: PlanDay, today: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        if day == today { return String(localized: "heute") }
        if day == today.adding(days: -1, calendar: calendar) { return String(localized: "gestern") }
        return relativeDay(day, today: today, calendar: calendar, locale: locale)
    }

    /// "Mi., 18. Nov."
    static func date(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)
        style.timeZone = calendar.timeZone
        return day.startDate(in: calendar).formatted(style)
    }
}
