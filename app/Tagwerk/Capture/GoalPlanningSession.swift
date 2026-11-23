import Foundation
import TagwerkCore

/// What the cross-check of a goal proposal needs from the device and what never goes to ChatGPT: the body values, the weight and the
/// mean active energy, and the year for the age.
struct GoalGuardInput: Equatable, Sendable {
    var body: BodyProfileValues
    var weightKg: Double?
    var meanActiveKcal: Double?
    var year: Int
}

/// One conversation of the goal planning as the device holds it: the package the user selected (frozen when the conversation began; it
/// is the exact value the sheet showed) and the input of the cross-check. It lives in memory only and ends with the conversation.
struct GoalPlanningSession: Equatable, Sendable {
    var package: GoalDataSummary
    var guardInput: GoalGuardInput
}
