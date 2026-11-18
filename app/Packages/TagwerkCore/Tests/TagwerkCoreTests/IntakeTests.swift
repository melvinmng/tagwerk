import Foundation
import Testing
@testable import TagwerkCore

struct IntakeTests {
    let calendar = makeCalendar()
    /// Wednesday, 18 Nov 2026, 12:00 in Berlin.
    var now: Date { instant(2026, 11, 18, 12, 0, in: calendar) }

    private func item(_ name: String, _ kcal: Double, min: Double? = nil, max: Double? = nil, protein: Double = 0,
                      factor: Double = 1) -> MealItem {
        MealItem(name: name, amount: "1 Portion", factor: factor, kcalMin: min ?? kcal, kcal: kcal, kcalMax: max ?? kcal,
                 protein: protein, carbs: 0, fat: 0, isEstimated: true)
    }

    private func meal(_ title: String, at date: Date, items: [MealItem], origin: MealOrigin = .estimated) -> MealValue {
        MealValue(id: UUID(), date: date, kind: .lunch, title: title, items: items, origin: origin)
    }

    private func workout(start: Date, minutes: Int, own: Bool = true) -> WorkoutValue {
        WorkoutValue(id: UUID().uuidString, activity: .running, start: start, minutes: minutes, kilocalories: nil,
                     sourceName: own ? nil : "Apple Watch", isOwn: own)
    }

    // MARK: Meal kind

    @Test func mealKind_byTime() {
        func kind(_ hour: Int, _ minute: Int) -> MealKind {
            MealKind.forTime(instant(2026, 11, 18, hour, minute, in: calendar), calendar: calendar)
        }
        #expect(kind(4, 59) == .snack)
        #expect(kind(5, 0) == .breakfast)
        #expect(kind(10, 29) == .breakfast)
        #expect(kind(10, 30) == .snack)
        #expect(kind(11, 30) == .lunch)
        #expect(kind(14, 29) == .lunch)
        #expect(kind(14, 30) == .snack)
        #expect(kind(17, 30) == .dinner)
        #expect(kind(21, 29) == .dinner)
        #expect(kind(22, 0) == .snack)
        #expect(MealKind.lunch.germanName == "Mittagessen")
    }

    // MARK: Sums

    @Test func item_factorScalesValues() {
        let scaled = item("Brötchen", 150, min: 120, max: 180, protein: 5, factor: 1.5)
        #expect(scaled.totalKcal == 225)
        #expect(scaled.totalKcalMin == 180)
        #expect(scaled.totalKcalMax == 270)
        #expect(scaled.totalProtein == 7.5)
    }

    @Test func dayIntake_sumsMealsAndWater_rangeFromMinMax() {
        let meals = [
            meal("Brötchen", at: now, items: [item("Brötchen", 300, min: 250, max: 350), item("Käse", 180, min: 150, max: 220)]),
            meal("Apfel", at: now, items: [item("Apfel", 80, min: 70, max: 90)], origin: .manual),
        ]
        let drinks = [DrinkValue(id: UUID(), date: now, milliliters: 250), DrinkValue(id: UUID(), date: now, milliliters: 500)]
        let intake = IntakeRules.dayIntake(meals: meals, drinks: drinks)
        #expect(intake.kcal == 560)
        #expect(intake.kcalMin == 470)
        #expect(intake.kcalMax == 660)
        #expect(intake.waterMilliliters == 750)
        #expect(intake.hasEstimate)
    }

    @Test func overriddenItem_losesTilde_sumKeepsTildeWhileAnyEstimated() {
        let overridden = item("Brötchen", 300, min: 250, max: 350).overridden(kcal: 320, protein: 9, carbs: 50, fat: 3)
        #expect(!overridden.isEstimated)
        #expect(overridden.kcalMin == 320 && overridden.kcalMax == 320)
        let mixed = meal("Brötchen", at: now, items: [overridden, item("Käse", 180, min: 150, max: 220)])
        #expect(mixed.hasEstimate)
        let manualOnly = meal("Brötchen", at: now, items: [overridden])
        #expect(!manualOnly.hasEstimate)
        #expect(!IntakeRules.dayIntake(meals: [manualOnly], drinks: []).hasEstimate)
    }

    @Test func item_decodesWithoutID_andKeepsIDOnOverride() throws {
        let json = #"{"name":"Apfel","amount":"","factor":1,"kcalMin":80,"kcal":80,"kcalMax":80,"protein":0,"carbs":20,"fat":0}"#
        let decoded = try JSONDecoder().decode(MealItem.self, from: Data(json.utf8))
        #expect(decoded.name == "Apfel" && !decoded.isEstimated)
        #expect(decoded.overridden(kcal: 90, protein: 0, carbs: 0, fat: 0).id == decoded.id)
        let roundTrip = try JSONDecoder().decode(MealItem.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func dayIntake_manualOnly_hasNoEstimate() {
        let manual = MealItem(name: "Apfel", amount: "", kcalMin: 80, kcal: 80, kcalMax: 80, protein: 0, carbs: 0, fat: 0)
        let intake = IntakeRules.dayIntake(meals: [meal("Apfel", at: now, items: [manual], origin: .manual)], drinks: [])
        #expect(!intake.hasEstimate)
        #expect(intake.kcal == 80)
    }

    // MARK: Workouts

    @Test func weekCount_mondayToSunday_minimum10Minutes() {
        let monday = instant(2026, 11, 16, 7, 0, in: calendar)
        let sunday = instant(2026, 11, 22, 20, 0, in: calendar)
        let nextMonday = instant(2026, 11, 23, 7, 0, in: calendar)
        let lastSunday = instant(2026, 11, 15, 20, 0, in: calendar)
        let workouts = [
            workout(start: monday, minutes: 30),
            workout(start: sunday, minutes: 10, own: false),
            workout(start: now, minutes: 9),
            workout(start: nextMonday, minutes: 60),
            workout(start: lastSunday, minutes: 60),
        ]
        #expect(IntakeRules.workoutsThisWeek(workouts, now: now, calendar: calendar) == 2)
    }

    @Test func overlap_detected_adjacentNot() {
        let watch = workout(start: instant(2026, 11, 18, 7, 0, in: calendar), minutes: 30, own: false)
        let overlapping = DateInterval(start: instant(2026, 11, 18, 7, 20, in: calendar), duration: 1800)
        let adjacent = DateInterval(start: instant(2026, 11, 18, 7, 30, in: calendar), duration: 1800)
        #expect(IntakeRules.overlappingWorkout(overlapping, in: [watch]) == watch)
        #expect(IntakeRules.overlappingWorkout(adjacent, in: [watch]) == nil)
    }

    // MARK: Repeat suggestions

    @Test func repeatSuggestions_rankByCountThenRecency_hiddenExcluded_filtered_limited() {
        func day(_ offset: Int) -> Date { now.addingTimeInterval(TimeInterval(-offset * 86_400)) }
        var meals = [
            meal("Müsli", at: day(1), items: [item("Müsli", 400)]),
            meal("müsli ", at: day(3), items: [item("Müsli", 400)]),
            meal("Pizza", at: day(2), items: [item("Pizza", 900)]),
            meal("Salat", at: day(1), items: [item("Salat", 300)]),
            meal("Suppe", at: day(31), items: [item("Suppe", 200)]),
            meal("Kuchen", at: day(1), items: [item("Kuchen", 350)]),
        ]
        let ranked = IntakeRules.repeatSuggestions(meals: meals, hidden: ["kuchen"], filter: "", now: now, calendar: calendar)
        // Müsli twice; Salat (1 day ago) is more recent than Pizza (2 days ago); Suppe is older than 30 days.
        #expect(ranked.map(\.title) == ["Müsli", "Salat", "Pizza"])

        let filtered = IntakeRules.repeatSuggestions(meals: meals, hidden: [], filter: "sa", now: now, calendar: calendar)
        #expect(filtered.map(\.title) == ["Salat"])

        meals = (0..<12).map { meal("Gericht \($0)", at: day(1), items: [item("x", 100)]) }
        #expect(IntakeRules.repeatSuggestions(meals: meals, hidden: [], filter: "", now: now, calendar: calendar).count == 8)
    }

    // MARK: AI estimate

    @Test func estimate_decode_normalizes() throws {
        let json = """
        {"title":"Brötchen mit Käse","items":[
          {"name":"Brötchen","amount":"2 Stück","kcal_min":350,"kcal":300,"kcal_max":280,"protein_g":10,"carbs_g":56,"fat_g":2},
          {"name":"Käse","amount":"2 Scheiben","kcal_min":-5,"kcal":180,"kcal_max":220,"protein_g":-1,"carbs_g":0,"fat_g":14},
          {"name":"Unsinn","amount":"","kcal_min":6000,"kcal":7000,"kcal_max":8000,"protein_g":0,"carbs_g":0,"fat_g":0}
        ]}
        """
        let estimate = try #require(try MealEstimateOutput.decode(Data(json.utf8)).normalized())
        #expect(estimate.title == "Brötchen mit Käse")
        #expect(estimate.items.count == 2)
        let roll = estimate.items[0]
        #expect(roll.kcalMin == 280 && roll.kcal == 300 && roll.kcalMax == 350)
        #expect(roll.isEstimated)
        let cheese = estimate.items[1]
        #expect(cheese.kcalMin == 0 && cheese.protein == 0)
    }

    @Test func estimate_tooManyItems_cut() throws {
        let items = (0..<25).map { #"{"name":"P\#($0)","amount":"","kcal_min":1,"kcal":2,"kcal_max":3,"protein_g":0,"carbs_g":0,"fat_g":0}"# }
        let json = #"{"title":"Buffet","items":[\#(items.joined(separator: ","))]}"#
        let estimate = try #require(try MealEstimateOutput.decode(Data(json.utf8)).normalized())
        #expect(estimate.items.count == 20)
    }

    @Test func estimate_emptyItems_isNothingRecognized() throws {
        let json = #"{"title":"","items":[]}"#
        #expect(try MealEstimateOutput.decode(Data(json.utf8)).normalized() == nil)
    }

    // MARK: Format

    @Test func format_estimate_tilde_range() {
        #expect(IntakeFormat.kcal(523, estimated: true) == "~520 kcal")
        #expect(IntakeFormat.kcal(1238, estimated: true) == "~1.240 kcal")
        #expect(IntakeFormat.range(min: 412, max: 548) == "wahrscheinlich zwischen 410 und 550 kcal")
        #expect(IntakeFormat.shortRange(min: 412, max: 548) == "410–550")
        #expect(IntakeFormat.rangeIfEstimated(min: 300, max: 300) == nil)
        #expect(IntakeFormat.rangeIfEstimated(min: 412, max: 548) == "wahrscheinlich zwischen 410 und 550 kcal")
    }

    @Test func format_manual_noTilde() {
        #expect(IntakeFormat.kcal(80, estimated: false) == "80 kcal")
        #expect(IntakeFormat.kcal(95, estimated: false) == "95 kcal")
        #expect(IntakeFormat.kcalNumber(1312, estimated: true) == "~1.310")
        #expect(IntakeFormat.kcalNumber(95, estimated: false) == "95")
        #expect(IntakeFormat.factor(1.5) == "×1,5")
        #expect(IntakeFormat.factor(2) == "×2")
        #expect(IntakeFormat.grams(21.6, estimated: true) == "~22 g")
        #expect(IntakeFormat.grams(5, estimated: false) == "5 g")
    }

    @Test func format_remaining() {
        var intake = DayIntake(kcal: 1310, kcalMin: 1100, kcalMax: 1500, protein: 0, carbs: 0, fat: 0, waterMilliliters: 0,
                               hasEstimate: true)
        #expect(IntakeFormat.remaining(goal: 2300, intake: intake) == .init(text: "noch ~990", isOver: false))
        intake.hasEstimate = false
        #expect(IntakeFormat.remaining(goal: 2300, intake: intake) == .init(text: "noch 990", isOver: false))
        intake.kcal = 2420
        #expect(IntakeFormat.remaining(goal: 2300, intake: intake) == .init(text: "120 über Ziel", isOver: true))
        intake.kcal = 2315
        #expect(IntakeFormat.remaining(goal: 2300, intake: intake) == .init(text: "15 über Ziel", isOver: true))
        intake.hasEstimate = true
        #expect(IntakeFormat.remaining(goal: 2300, intake: intake) == .init(text: "~20 über Ziel", isOver: true))
    }

    @Test func format_liters_andSummary() {
        #expect(IntakeFormat.liters(1200) == "1,2 l")
        #expect(IntakeFormat.liters(2000) == "2,0 l")
        #expect(IntakeFormat.liters(250) == "0,25 l")
        #expect(IntakeFormat.goalSummary(kcal: 2300, waterMilliliters: 2000, workoutsPerWeek: 3) == "2.300 kcal · 2,0 l · 3×")
    }
}
