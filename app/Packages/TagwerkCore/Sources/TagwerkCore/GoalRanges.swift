import Foundation

/// The limits of every goal value. The settings screens (steppers) and the checks of the goal planning (a proposal of ChatGPT, a
/// card the user adjusted) use these ranges, so the two cannot drift apart. They are input limits, not recommendations.
public enum GoalRanges {
    public static let kcal = 1000...6000
    public static let waterMilliliters = 500...6000
    public static let stepsPerDay = 0...30000
    public static let workoutMinutesPerWeek = 0...1200
    public static let proteinGrams = 20...400
    public static let carbsGrams = 20...800
    public static let fatGrams = 10...400
    public static let fiberGrams = 5...100
    public static let sugarLimitGrams = 5...250
    /// 0 switches the goal off.
    public static let activeKcalPerDay = 0...3000
    public static let targetWeightKg = WeightRules.minimumKilograms...WeightRules.maximumKilograms
    /// Intended weekly change in kilograms; negative for losing weight.
    public static let paceKgPerWeek = -2.0...1.0
}
