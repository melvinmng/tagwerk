import Foundation
import Observation
import RemindersKit

/// Steps of the first-launch setup.
enum SetupStep: CaseIterable, Hashable {
    case reminders, calendar, planCalendar, github, chatGPT, notifications

    var title: String {
        switch self {
        case .reminders: String(localized: "Erinnerungen")
        case .calendar: String(localized: "Kalender")
        case .planCalendar: String(localized: "Plan-Kalender")
        case .github: "GitHub"
        case .chatGPT: "ChatGPT"
        case .notifications: String(localized: "Benachrichtigungen")
        }
    }

    var explanation: String {
        switch self {
        case .reminders: String(localized: "Tagwerk zeigt deine Erinnerungen zusammen mit deinen anderen Aufgaben und kann sie bearbeiten.")
        case .calendar: String(localized: "Tagwerk liest deine Termine, um deinen Tag zu planen. Der Kalender wird nicht verändert.")
        case .planCalendar: String(localized: "Tagwerk legt geplante Zeitblöcke als Termine in einem eigenen Kalender „Tagwerk“ an. Du siehst sie auch in der Kalender-App.")
        case .github: String(localized: "Tagwerk zeigt dir zugewiesene Issues aus deinen offenen GitHub Projects und kann sie bearbeiten.")
        case .chatGPT: String(localized: "Mit deinem ChatGPT-Konto kann Tagwerk Tag, Woche und Monat für dich planen, und der Assistent kann Aufgaben für dich ändern.")
        case .notifications: String(localized: "Tagwerk erinnert dich vor der Fälligkeit an GitHub- und lokale Aufgaben und an Termine aus deinen Deadline-Kalendern. Erinnerungen aus der App „Erinnerungen“ melden sich weiterhin selbst.")
        }
    }

    /// Shown next to a step that was skipped or refused.
    var notDoneLabel: String {
        self == .chatGPT ? String(localized: "nicht angemeldet") : String(localized: "nicht erlaubt")
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
    /// Asks iOS for notification permission; `true` when granted.
    private let requestNotifications: () async -> Bool

    init(store: any ReminderStore, settings: AppSettings, calendarStore: (any CalendarStore)? = nil,
         isChatGPTSignedIn: Bool = false, notificationsAllowed: Bool = false,
         requestNotifications: @escaping () async -> Bool = { false }) {
        self.store = store
        self.settings = settings
        self.calendarStore = calendarStore
        self.requestNotifications = requestNotifications
        // After "Einrichtung erneut starten" an existing ChatGPT sign-in or permission counts as done.
        if isChatGPTSignedIn { results[.chatGPT] = .fullAccess }
        if notificationsAllowed { results[.notifications] = .fullAccess }
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
            case .notifications: results[step] = await requestNotifications() ? .fullAccess : .denied
            case .github, .chatGPT: return  // interactive login, completed via markSignedIn()
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
        if current == .chatGPT { results[.chatGPT] = .denied }
        advance()
    }

    /// Records an existing ChatGPT sign-in that became known after the setup started.
    func noteChatGPTSignedIn() {
        results[.chatGPT] = .fullAccess
        if current == .chatGPT { advance() }
    }

    /// Completes a login step (GitHub, ChatGPT) after a successful sign-in.
    func markSignedIn() {
        guard let step = current, step == .github || step == .chatGPT else { return }
        results[step] = .fullAccess
        advance()
    }

    private func advance() {
        guard let step = current, let index = SetupStep.allCases.firstIndex(of: step) else { return }
        let next = SetupStep.allCases.index(after: index)
        current = next < SetupStep.allCases.endIndex ? SetupStep.allCases[next] : nil
        // A ChatGPT step that is already signed in, or a permission already given, needs no action.
        if let next = current, next == .chatGPT || next == .notifications, results[next] == .fullAccess {
            advance()
            return
        }
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
