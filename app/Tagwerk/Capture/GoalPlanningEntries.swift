import SwiftUI

/// The entries into the goal planning (decisions ZI1b, ZI6b): "Ziele planen" and "Fortschritt besprechen". Each one opens the consent
/// (when it is missing), the data sheet and then the chat; the first message of the review is prepared and sent only on a tap. Without a
/// ChatGPT sign-in the buttons are off and a hint names the way. A `Section` for a list or form; the sheets hang on the root view.
struct GoalPlanningEntries: View {
    enum Offer {
        case planAndReview, planOnly, reviewOnly
    }

    var offer = Offer.planAndReview
    /// A line above the footer, e.g. the age of the goals in the weekly review; `nil` leaves the footer as it is.
    var note: String?
    @Environment(AppEnvironment.self) private var environment

    private var flow: GoalPlanningFlow { environment.goalPlanning }
    private var isSignedIn: Bool { environment.ai.isSignedIn }

    var body: some View {
        Section {
            if offer != .reviewOnly {
                Button {
                    Task { await flow.start(.plan) }
                } label: {
                    Label("Ziele planen", systemImage: "sparkles")
                }
                .disabled(!isSignedIn || flow.isPreparing)
                .accessibilityIdentifier(AccessibilityID.GoalPlanning.planEntry)
            }
            if offer != .planOnly {
                Button {
                    Task { await flow.start(.review) }
                } label: {
                    Label("Fortschritt besprechen", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(!isSignedIn || flow.isPreparing)
                .accessibilityIdentifier(AccessibilityID.GoalPlanning.reviewEntry)
            }
        } footer: {
            if let note { Text(note) }
            if isSignedIn {
                Text("Du wählst vor jedem Gespräch aus, was an ChatGPT geht. Es geht nichts weg, bevor du das Gespräch beginnst. Tagwerk gibt keine medizinische Beratung.")
            } else {
                Text("Melde dich unter Einstellungen › KI bei ChatGPT an, um Ziele planen zu lassen.")
                    .accessibilityIdentifier(AccessibilityID.GoalPlanning.signInHint)
            }
        }
    }
}
