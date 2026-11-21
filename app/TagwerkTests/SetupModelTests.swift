import Foundation
import RemindersKit
import SwiftData
import Testing
@testable import Tagwerk

@MainActor
struct SetupModelTests {
    let container: ModelContainer
    let settings: AppSettings
    let store = FakeAccessStore()

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        store.calendarInfos = [
            ListInfo(id: "work", title: "Arbeit", colorHex: nil, kind: .calDAV),
            ListInfo(id: "holidays", title: "Feiertage", colorHex: nil, kind: .subscription),
        ]
    }

    /// German UI text says "Projekt", not "Project" (G1).
    @Test func githubExplanation_writesProjekt() {
        #expect(SetupStep.github.explanation.contains("GitHub-Projekten"))
        #expect(!SetupStep.github.explanation.contains("Project"))
    }

    @Test func grant_reminders_advancesToCalendar() async {
        let model = SetupModel(store: store, settings: settings)
        #expect(model.current == .reminders)
        await model.grant()
        #expect(store.reminderRequests == 1)
        #expect(model.results[.reminders] == .fullAccess)
        #expect(model.current == .calendar)
    }

    @Test func skip_reminders_advancesWithoutRequest() {
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        #expect(store.reminderRequests == 0)
        #expect(model.current == .calendar)
    }

    @Test func grant_denied_recordsDeniedAndAdvances() async {
        store.reminderAnswer = .denied
        let model = SetupModel(store: store, settings: settings)
        await model.grant()
        #expect(model.results[.reminders] == .denied)
        #expect(model.current == .calendar)
    }

    @Test func finish_setsDefaultCalendarSelection() async {
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        await model.grant()
        #expect(store.calendarRequests == 1)
        #expect(model.current == .planCalendar)
        model.skip()
        #expect(model.current == .github)
        model.skip()
        #expect(model.current == .chatGPT)
        model.skip()
        #expect(model.current == .notifications)
        model.skip()
        #expect(model.isFinished)
        #expect(settings.selectedCalendarIDs == ["work"])
    }

    @Test func finish_setsDefaultCalendarSelectionOnce() async {
        settings.selectedCalendarIDs = ["holidays"]
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        await model.grant()
        model.skip()
        model.skip()
        #expect(settings.selectedCalendarIDs == ["holidays"])
    }

    @Test func finish_withoutCalendarAccess_keepsSelectionNil() async {
        store.calendarAnswer = .denied
        store.calendarInfos = []
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        await model.grant()
        model.skip()
        model.skip()
        #expect(settings.selectedCalendarIDs == nil)
    }

    @Test func finish_marksSetupCompleted() {
        let model = SetupModel(store: store, settings: settings)
        for _ in 0..<5 { model.skip() }
        #expect(!settings.setupCompleted)
        model.skip()
        #expect(model.isFinished)
        #expect(settings.setupCompleted)
    }

    @Test func githubStep_markSignedIn_recordsAndFinishes() async {
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        model.skip()
        model.skip()
        #expect(model.current == .github)
        model.markSignedIn()
        #expect(model.results[.github] == .fullAccess)
        #expect(model.current == .chatGPT)
    }

    @Test func chatGPTStep_markSignedIn_recordsAndAdvancesToNotifications() async {
        let model = SetupModel(store: store, settings: settings)
        for _ in 0..<4 { model.skip() }
        #expect(model.current == .chatGPT)
        model.markSignedIn()
        #expect(model.results[.chatGPT] == .fullAccess)
        #expect(model.current == .notifications)
        #expect(!settings.setupCompleted)
    }

    @Test func chatGPTStep_skip_isMarkedNotSignedIn() async {
        let model = SetupModel(store: store, settings: settings)
        for _ in 0..<5 { model.skip() }
        #expect(model.results[.chatGPT] == .denied)
        model.skip()
        #expect(SetupStep.chatGPT.notDoneLabel == "nicht angemeldet")
        #expect(SetupStep.reminders.notDoneLabel == "nicht erlaubt")
        #expect(model.isFinished)
    }

    @Test func chatGPTStep_alreadySignedIn_isDoneAndSkipped() async {
        let model = SetupModel(store: store, settings: settings, isChatGPTSignedIn: true)
        for _ in 0..<4 { model.skip() }
        #expect(model.results[.chatGPT] == .fullAccess)
        #expect(model.current == .notifications)
    }

    @Test func chatGPTSignInKnownLater_whileOnStep_finishes() async {
        let model = SetupModel(store: store, settings: settings)
        for _ in 0..<4 { model.skip() }
        model.noteChatGPTSignedIn()
        #expect(model.results[.chatGPT] == .fullAccess)
        #expect(model.current == .notifications)
    }

    @Test func steps_haveGermanTitles() {
        #expect(SetupStep.allCases.map(\.title) == ["Erinnerungen", "Kalender", "Plan-Kalender", "GitHub", "ChatGPT",
                                                    "Benachrichtigungen"])
    }

    @Test func planCalendarStep_createsTagwerkCalendar() async {
        let calendars = FakeCalendarStore()
        let model = SetupModel(store: store, settings: settings, calendarStore: calendars)
        model.skip()
        await model.grant()
        #expect(model.current == .planCalendar)
        await model.grant()
        #expect(settings.planCalendarID == "new-plan")
        #expect(calendars.calendars.contains { $0.title == "Tagwerk" })
        #expect(model.current == .github)
    }

    @Test func planCalendarStep_skip_leavesNil() async {
        let model = SetupModel(store: store, settings: settings, calendarStore: FakeCalendarStore())
        model.skip()
        model.skip()
        model.skip()
        #expect(settings.planCalendarID == nil)
    }

    @Test func planCalendarStep_withoutCalendarAccess_isDenied() async {
        store.calendarAnswer = .denied
        let calendars = FakeCalendarStore()
        let model = SetupModel(store: store, settings: settings, calendarStore: calendars)
        model.skip()
        await model.grant()
        await model.grant()
        #expect(model.results[.planCalendar] == .denied)
        #expect(settings.planCalendarID == nil)
    }

    @Test func notificationsStep_grant_requestsAuthorizationAndFinishes() async {
        var requests = 0
        let model = SetupModel(store: store, settings: settings, requestNotifications: {
            requests += 1
            return true
        })
        for _ in 0..<5 { model.skip() }
        #expect(model.current == .notifications)
        await model.grant()
        #expect(requests == 1)
        #expect(model.results[.notifications] == .fullAccess)
        #expect(model.isFinished)
        #expect(settings.setupCompleted)
    }

    @Test func notificationsStep_refused_recordsDenied() async {
        let model = SetupModel(store: store, settings: settings, requestNotifications: { false })
        for _ in 0..<5 { model.skip() }
        await model.grant()
        #expect(model.results[.notifications] == .denied)
        #expect(SetupStep.notifications.notDoneLabel == "nicht erlaubt")
        #expect(model.isFinished)
    }

    @Test func notificationsStep_skip_finishesWithoutRequest() async {
        var requests = 0
        let model = SetupModel(store: store, settings: settings, requestNotifications: {
            requests += 1
            return true
        })
        for _ in 0..<6 { model.skip() }
        #expect(requests == 0)
        #expect(model.isFinished)
    }

    @Test func notificationsStep_alreadyAllowed_isDoneAndSkipped() async {
        let model = SetupModel(store: store, settings: settings, notificationsAllowed: true)
        for _ in 0..<5 { model.skip() }
        #expect(model.results[.notifications] == .fullAccess)
        #expect(model.isFinished)
    }
}
