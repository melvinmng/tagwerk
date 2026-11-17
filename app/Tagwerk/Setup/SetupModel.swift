import Foundation
import Observation
import RemindersKit

/// Steps of the first-launch setup. GitHub, ChatGPT and notifications are added by later plans.
enum SetupStep: CaseIterable, Hashable {
    case reminders, calendar, planCalendar, github

    var title: String {
        switch self {
        case .reminders: "Erinnerungen"
        case .calendar: "Kalender"
        case .planCalendar: "Plan-Kalender"
        case .github: "GitHub"
        }
    }

    var explanation: String {
        switch self {
        case .reminders: "Tagwerk zeigt deine Erinnerungen zusammen mit deinen anderen Aufgaben und kann sie bearbeiten."
        case .calendar: "Tagwerk liest deine Termine, um deinen Tag zu planen. Der Kalender wird nicht verändert."
        case .planCalendar: "Tagwerk legt geplante Zeitblöcke als Termine in einem eigenen Kalender „Tagwerk“ an. Du siehst sie auch in der Kalender-App."
        case .github: "Tagwerk zeigt dir zugewiesene Issues aus deinen offenen GitHub Projects und kann sie bearbeiten."
        }
    }
}

/// Guided setup (mockup 4). Every step can be skipped.
@MainActor
@Observable
final class SetupModel {
    private(set) var current: SetupStep? = SetupStep.allCases.first
    private(set) var results: [SetupStep: AccessState] = [:]

    private let store: any ReminderStore
    private let settings: AppSettings
    private let calendarStore: (any CalendarStore)?

    init(store: any ReminderStore, settings: AppSettings, calendarStore: (any CalendarStore)? = nil) {
        self.store = store
        self.settings = settings
        self.calendarStore = calendarStore
    }

    var isFinished: Bool { current == nil }

    /// Requests access for the current step, records the answer and moves on.
    func grant() async {
        guard let step = current else { return }
        do {
            switch step {
            case .reminders: results[step] = try await store.requestAccess()
            case .calendar: results[step] = try await store.requestCalendarAccess()
            case .planCalendar: results[step] = try createPlanCalendar()
            case .github: return  // interactive login, completed via markSignedIn()
            }
        } catch {
            results[step] = .denied
        }
        advance()
    }

    /// Uses an existing plan calendar or creates "Tagwerk"; needs full calendar access.
    private func createPlanCalendar() throws -> AccessState {
        guard store.calendarAccessState == .fullAccess, let calendarStore else { return .denied }
        if calendarStore.planCalendar(id: settings.planCalendarID) == nil {
            settings.planCalendarID = try calendarStore.createPlanCalendar(named: "Tagwerk").id
        }
        return .fullAccess
    }

    func skip() {
        advance()
    }

    /// Completes the GitHub step after a successful login.
    func markSignedIn() {
        guard current == .github else { return }
        results[.github] = .fullAccess
        advance()
    }

    private func advance() {
        guard let step = current, let index = SetupStep.allCases.firstIndex(of: step) else { return }
        let next = SetupStep.allCases.index(after: index)
        current = next < SetupStep.allCases.endIndex ? SetupStep.allCases[next] : nil
        if current == nil { finish() }
    }

    private func finish() {
        // Only store a default when calendars are visible; an empty list would hide all calendars later.
        let calendars = store.calendars()
        if settings.selectedCalendarIDs == nil, !calendars.isEmpty {
            settings.selectedCalendarIDs = CalendarSelection.defaultSelected(calendars).sorted()
        }
        settings.setupCompleted = true
    }
}
