import Foundation
import Observation
import TagwerkCore

/// The way into the chat "Ziele planen" (decisions ZI6b, PV1b, PV2a): sign-in, then the consent (once), then the sheet that shows
/// the data package, then the chat. "Ziele planen" and "Fortschritt besprechen" use the same way; the second prepares the first message
/// ("Fortschritt besprechen") without sending it, and takes the period since the current goals. Nothing is sent before the user taps
/// "Gespräch beginnen" and then writes or sends a message.
///
/// The sheets hang on the root view (`stage`); the chat opens after the data sheet has been dismissed (`finishPresentation`), because a
/// sheet cannot be presented while another one is still leaving.
@MainActor
@Observable
final class GoalPlanningFlow {
    enum Purpose: Equatable {
        case plan
        case review
    }

    enum Stage: Identifiable, Equatable {
        case consent
        case data(GoalPlanningSession)

        var id: String {
            switch self {
            case .consent: "consent"
            case .data: "data"
            }
        }
    }

    private(set) var stage: Stage?
    /// The data is being collected (a short moment, Health may be asked).
    private(set) var isPreparing = false
    private(set) var purpose = Purpose.plan

    private let settings: AppSettings
    private let builder: GoalDataBuilder
    private let assistant: AssistantModel
    private let isSignedIn: () -> Bool
    @ObservationIgnored private var pending: (session: GoalPlanningSession, prefill: String?)?
    /// The consent sheet was agreed to; the data sheet follows when it has left.
    @ObservationIgnored private var continuesWithData = false

    init(settings: AppSettings, builder: GoalDataBuilder, assistant: AssistantModel, isSignedIn: @escaping () -> Bool) {
        self.settings = settings
        self.builder = builder
        self.assistant = assistant
        self.isSignedIn = isSignedIn
    }

    /// The first message that "Fortschritt besprechen" prepares.
    static var reviewPrefill: String {
        String(localized: "Ich möchte besprechen, wie mein Fortschritt seit meinen letzten Zielen aussieht und ob sie noch passen.")
    }

    // MARK: Entry

    /// Starts the way. Without a sign-in nothing happens (the entries show the hint); without the consent the consent sheet comes first.
    func start(_ purpose: Purpose) async {
        guard isSignedIn(), stage == nil, !isPreparing else { return }
        self.purpose = purpose
        if !settings.goalPlanningConsent {
            stage = .consent
            return
        }
        await prepareData()
    }

    /// "Einverstanden und weiter" on the consent sheet: the data sheet follows when the consent sheet has left (`finishPresentation`).
    func agree() {
        settings.goalPlanningConsent = true
        continuesWithData = true
        stage = nil
    }

    /// "Nicht jetzt": nothing was sent, nothing is stored.
    func decline() {
        continuesWithData = false
        stage = nil
    }

    /// The system dismissed the sheet (swipe): the stage ends, a begun conversation stays pending.
    func dismissed() {
        stage = nil
    }

    private func prepareData() async {
        isPreparing = true
        defer { isPreparing = false }
        let days = purpose == .review ? builder.reviewPeriodDays() : GoalDataBuilder.standardDays
        let session = await builder.build(periodDays: days)
        // The consent may have been withdrawn while the data was collected.
        guard settings.goalPlanningConsent else { stage = nil; return }
        stage = .data(session)
    }

    // MARK: Data sheet

    /// The groups that start switched on: all that hold content except the ones the user switched off last time.
    func initialSelection(for package: GoalDataSummary) -> Set<GoalDataGroup> {
        Set(package.groups).subtracting(settings.goalDataOffGroups)
    }

    /// "Gespräch beginnen": remembers the switches, freezes the selection and opens the chat when the sheet has left.
    func begin(selected: Set<GoalDataGroup>, draft: GoalPlanningSession) {
        settings.goalDataOffGroups = Set(draft.package.groups).subtracting(selected)
        var session = draft
        session.package = draft.package.keeping(selected)
        pending = (session, purpose == .review ? Self.reviewPrefill : nil)
        stage = nil
    }

    func cancel() {
        pending = nil
        continuesWithData = false
        stage = nil
    }

    /// Called when a sheet has been dismissed: after the consent sheet the data is collected and shown, after the data sheet the chat
    /// opens for a begun conversation. A sheet cannot be presented while another one is still leaving, so the next step waits for this.
    func finishPresentation() async {
        if continuesWithData {
            continuesWithData = false
            await prepareData()
            return
        }
        guard let pending else { return }
        self.pending = nil
        assistant.openGoals(session: pending.session, prefill: pending.prefill)
    }
}
