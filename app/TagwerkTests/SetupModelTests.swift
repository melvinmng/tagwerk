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
        #expect(model.current == .github)
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
        #expect(settings.selectedCalendarIDs == ["holidays"])
    }

    @Test func finish_withoutCalendarAccess_keepsSelectionNil() async {
        store.calendarAnswer = .denied
        store.calendarInfos = []
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        await model.grant()
        model.skip()
        #expect(settings.selectedCalendarIDs == nil)
    }

    @Test func finish_marksSetupCompleted() {
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        model.skip()
        #expect(!settings.setupCompleted)
        model.skip()
        #expect(model.isFinished)
        #expect(settings.setupCompleted)
    }

    @Test func githubStep_markSignedIn_recordsAndFinishes() async {
        let model = SetupModel(store: store, settings: settings)
        model.skip()
        model.skip()
        #expect(model.current == .github)
        model.markSignedIn()
        #expect(model.results[.github] == .fullAccess)
        #expect(model.isFinished)
    }

    @Test func steps_haveGermanTitles() {
        #expect(SetupStep.allCases.map(\.title) == ["Erinnerungen", "Kalender", "GitHub"])
    }
}
