import Foundation
import TagwerkCore

/// Texts of the habits (phase 7 design §7.1, §7.2). German is the source language; the catalogs carry English.
enum HabitText {
    /// SF Symbols a habit can wear.
    static let symbols = ["checkmark.circle", "book", "figure.walk", "figure.run", "figure.strengthtraining.traditional",
                          "drop", "bed.double", "leaf", "pencil", "brain.head.profile", "heart", "sun.max", "fork.knife",
                          "music.note", "pills", "cup.and.saucer", "moon.stars", "sparkles",
                          // The symbols of the suggested habits, so the sheet of a taken-over habit shows its symbol selected.
                          "book.closed", "shower", "graduationcap", "book.pages"]

    /// "Gewohnheiten · 3 von 5" or "Gewohnheiten" without active habits.
    static func header(_ counter: HabitCounter?) -> String {
        guard let counter else { return String(localized: "Gewohnheiten") }
        return String(localized: "Gewohnheiten · \(counter.done) von \(counter.total)")
    }

    /// Under the name of a row: "7 Tage 5/7 · 30 Tage 73 % · Serie 3" or, with fewer than seven days a week,
    /// "Diese Woche 2 von 3 · 30 Tage 80 % · Serie 4 Wochen".
    static func subtitle(_ habit: Habit, today: PlanDay, facts: HabitFacts, calendar: Calendar) -> String {
        let first: String
        if habit.daysPerWeek >= 7 {
            let week = HabitRules.progress(habit, lastDays: 7, today: today, facts: facts, calendar: calendar)
            // "0/0" says nothing for a habit that has no counting day yet.
            first = week.counting == 0 ? String(localized: "7 Tage –") : String(localized: "7 Tage \(week.done)/\(week.counting)")
        } else {
            let week = HabitRules.weekProgress(habit, weekContaining: today, today: today, facts: facts, calendar: calendar)
            first = String(localized: "Diese Woche \(week.done) von \(week.goal)")
        }
        let rate = HabitRules.rate(habit, lastDays: 30, today: today, facts: facts, calendar: calendar)
            .map { "\($0) %" } ?? "–"
        let month = String(localized: "30 Tage \(rate)")
        let streak = streak(HabitRules.streak(habit, today: today, facts: facts, calendar: calendar))
        return [first, month, streak].joined(separator: " · ")
    }

    /// "Serie 3", "Serie 4 Wochen", "Serie 90+", "Serie 12+ Wochen".
    static func streak(_ streak: HabitStreak) -> String {
        switch streak {
        case .days(let count, let isCapped):
            return isCapped ? String(localized: "Serie \(count)+") : String(localized: "Serie \(count)")
        case .weeks(let count, let isCapped):
            if isCapped { return String(localized: "Serie \(count)+ Wochen") }
            return count == 1 ? String(localized: "Serie 1 Woche") : String(localized: "Serie \(count) Wochen")
        }
    }

    /// What fulfilled an automatic row: "2,1 l von 2,0 l", "Laufen 42 min aus Health"; `nil` for manual habits.
    static func sourceDetail(_ habit: Habit, on day: PlanDay, facts: HabitFacts, workout: WorkoutValue?,
                             locale: Locale = .current) -> String? {
        switch habit.source {
        case .manual:
            return nil
        case .water:
            let value = IntakeFormat.liters(facts.waterMilliliters[day] ?? 0, locale: locale)
            let goal = IntakeFormat.liters(facts.goalWaterMilliliters, locale: locale)
            return String(localized: "\(value) von \(goal)")
        case .workout:
            return workout.map(workoutDetail)
        case .steps:
            return stepsDetail(on: day, facts: facts, locale: locale)
        case .movement:
            // A counted workout names itself; otherwise the steps tell how far the day is.
            if facts.workoutDays.contains(day), let workout { return workoutDetail(workout) }
            return stepsDetail(on: day, facts: facts, locale: locale)
        case .daylight:
            let minutes = facts.daylightMinutes[day] ?? 0
            return String(localized: "\(minutes) von \(habit.daylightMinutes) min Tageslicht")
        case .eveningClosed:
            return facts.closedDays.contains(day) ? String(localized: "Tagesabschluss abgeschlossen") : nil
        case .journal:
            return facts.journalDays.contains(day) ? String(localized: "Tagebuch geschrieben") : nil
        case .bibleStudy:
            return facts.bibleStudyDays.contains(day) ? String(localized: "Sitzung abgeschlossen") : nil
        }
    }

    private static func workoutDetail(_ workout: WorkoutValue) -> String {
        let name = workout.displayName
        return workout.isOwn ? String(localized: "\(name) \(workout.minutes) min")
                             : String(localized: "\(name) \(workout.minutes) min aus Health")
    }

    /// "10.412 von 8.000 Schritten"; `nil` without a step goal (nothing to compare with).
    private static func stepsDetail(on day: PlanDay, facts: HabitFacts, locale: Locale) -> String? {
        guard facts.goalSteps > 0 else { return nil }
        let value = IntakeFormat.grouped(facts.steps[day] ?? 0, locale: locale)
        let goal = IntakeFormat.grouped(facts.goalSteps, locale: locale)
        return String(localized: "\(value) von \(goal) Schritten")
    }

    /// "Täglich", "3 Tage pro Woche".
    static func rhythm(_ daysPerWeek: Int) -> String {
        if daysPerWeek >= 7 { return String(localized: "Täglich") }
        return daysPerWeek == 1 ? String(localized: "1 Tag pro Woche") : String(localized: "\(daysPerWeek) Tage pro Woche")
    }

    /// The name of an automatic source in the picker.
    static func sourceTitle(_ source: HabitSource) -> String {
        switch source {
        case .manual: String(localized: "Von Hand abhaken")
        case .water: String(localized: "Wasserziel erreicht")
        case .workout: String(localized: "Training erfasst")
        case .steps: String(localized: "Schrittziel erreicht")
        case .movement: String(localized: "Bewegung")
        case .daylight: String(localized: "Zeit bei Tageslicht")
        case .eveningClosed: String(localized: "Tagesabschluss erledigt")
        case .journal: String(localized: "Tagebuch geschrieben")
        case .bibleStudy: String(localized: "Bible-Study-Sitzung abgeschlossen")
        }
    }

    /// The line under the name of a source in the picker; `nil` where the title says it all.
    static func sourceSubtitle(_ source: HabitSource) -> String? {
        source == .movement ? String(localized: "Training erfasst oder Schrittziel erreicht") : nil
    }

    // MARK: States of a row (GW2a, GW3b)

    /// Share of the goal for water and steps (0…1, never more); `nil` for sources without a measure: a workout, a closed evening, a
    /// journal entry, a Bible Study session, daylight, and "Bewegung" without a step goal.
    static func sourceProgress(_ habit: Habit, on day: PlanDay, facts: HabitFacts) -> Double? {
        switch habit.source {
        case .water:
            return share(facts.waterMilliliters[day] ?? 0, of: facts.goalWaterMilliliters)
        case .steps, .movement:
            return share(facts.steps[day] ?? 0, of: facts.goalSteps)
        case .manual, .workout, .daylight, .eveningClosed, .journal, .bibleStudy:
            return nil
        }
    }

    private static func share(_ value: Int, of goal: Int) -> Double? {
        goal > 0 ? min(1, max(0, Double(value) / Double(goal))) : nil
    }

    /// The line under the subtitle of a row, by state:
    /// (2) "Automatisch erfüllt · 2,1 l von 2,0 l", (3) "5.600 von 8.000 Schritten · hakt sich selbst ab",
    /// (4) "Von Hand abgehakt · Tagebuch noch offen"; `nil` for habits by hand. A source without a measure says
    /// "Tagebuch noch offen · hakt sich selbst ab" in (3).
    static func stateLine(_ row: HabitsModel.Row, on day: PlanDay, facts: HabitFacts, workout: WorkoutValue?,
                          locale: Locale = .current) -> String? {
        let habit = row.habit
        switch row.state {
        case .manualOpen, .manualDone:
            return nil
        case .automaticDone:
            let head = String(localized: "Automatisch erfüllt")
            return sourceDetail(habit, on: day, facts: facts, workout: workout, locale: locale).map { "\(head) · \($0)" } ?? head
        case .automaticPending(let progress):
            let measure = progress == nil ? nil : sourceDetail(habit, on: day, facts: facts, workout: nil, locale: locale)
            let first = measure ?? String(localized: "\(sourceNoun(habit.source)) noch offen")
            return "\(first) · " + String(localized: "hakt sich selbst ab")
        case .manualDoneSourcePending:
            return String(localized: "Von Hand abgehakt") + " · " + String(localized: "\(sourceNoun(habit.source)) noch offen")
        }
    }

    /// The source as a short noun, for "Tagebuch noch offen".
    static func sourceNoun(_ source: HabitSource) -> String {
        switch source {
        case .manual: ""
        case .water: String(localized: "Wasserziel")
        case .workout: String(localized: "Training")
        case .steps: String(localized: "Schrittziel")
        case .movement: String(localized: "Bewegung")
        case .daylight: String(localized: "Tageslicht")
        case .eveningClosed: String(localized: "Tagesabschluss")
        case .journal: String(localized: "Tagebuch")
        case .bibleStudy: String(localized: "Bible Study")
        }
    }

    /// What VoiceOver says for the state of a row, in words instead of the bolt.
    static func accessibilityState(_ state: HabitsModel.Row.State) -> String {
        switch state {
        case .manualOpen: String(localized: "offen")
        case .manualDone: String(localized: "erledigt")
        case .automaticDone: String(localized: "automatisch erfüllt")
        case .automaticPending: String(localized: "offen, hakt sich selbst ab")
        case .manualDoneSourcePending: String(localized: "von Hand abgehakt")
        }
    }
}
