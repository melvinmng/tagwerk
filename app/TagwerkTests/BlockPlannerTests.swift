import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct BlockPlannerTests {
    let container: ModelContainer
    let calendarStore = FakeCalendarStore()
    let planStore: PlanStore
    let settings: AppSettings
    let calendar = testCalendar()
    let issue = makeTask("Login-Fehler beheben", source: .github)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        planStore = PlanStore(context: container.mainContext)
        settings = try AppSettings.current(in: container.mainContext)
        settings.planCalendarID = "plan"
    }

    private func planner() -> BlockPlanner {
        BlockPlanner(store: calendarStore, planStore: planStore, links: EventLinkStore(context: container.mainContext),
                     settings: settings, calendar: calendar)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func createBlock_setsDayAssignmentTitleAndLink() throws {
        var github = issue
        github.url = URL(string: "https://github.com/beispiel/app/issues/42")
        let block = try planner().createBlock(for: github, start: at(19, 10), minutes: 90)
        #expect(block.title == "#42 Login-Fehler beheben")
        #expect(block.end == at(19, 11, 30))
        #expect(TaskLinkURL.parse(block.url!) == github.id)
        #expect(planStore.assignment(for: github.id) == PlanDay(year: 2026, month: 11, day: 19))
    }

    @Test func createBlock_withoutPlanCalendar_throws() {
        settings.planCalendarID = nil
        #expect(!planner().canWriteBlocks)
        #expect(throws: TaskWriteError.self) { try planner().createBlock(for: issue, start: at(19, 10), minutes: 30) }
    }

    @Test func moveFutureBlocks_keepsTimeAndSkipsPast() throws {
        let sut = planner()
        let past = try sut.createBlock(for: issue, start: at(17, 9), minutes: 60)
        let future = try sut.createBlock(for: issue, start: at(19, 14, 30), minutes: 60)
        try sut.moveFutureBlocks(of: issue.id, to: PlanDay(year: 2026, month: 11, day: 24), after: at(18, 12))
        #expect(calendarStore.event(id: past.id)?.start == at(17, 9))
        #expect(calendarStore.event(id: future.id)?.start == at(24, 14, 30))
        #expect(calendarStore.event(id: future.id)?.end == at(24, 15, 30))
    }

    @Test func deleteFutureBlocks_keepsPast() throws {
        let sut = planner()
        let past = try sut.createBlock(for: issue, start: at(17, 9), minutes: 60)
        _ = try sut.createBlock(for: issue, start: at(19, 9), minutes: 60)
        try sut.deleteFutureBlocks(of: issue.id, after: at(18, 0))
        #expect(calendarStore.storedEvents.map(\.id) == [past.id])
    }

    @Test func staleBlock_moveThrows() throws {
        let sut = planner()
        let block = try sut.createBlock(for: issue, start: at(19, 9), minutes: 60)
        _ = try calendarStore.moveBlock(id: block.id, to: at(19, 10), end: at(19, 11), expectedVersion: nil)  // edited elsewhere
        #expect(throws: TaskWriteError.self) {
            try sut.moveBlock(block, to: at(20, 9))
        }
    }

    @Test func manualLink_persists() {
        let links = EventLinkStore(context: container.mainContext)
        links.link(eventID: "e1", to: issue.id)
        #expect(EventLinkStore(context: container.mainContext).manualLinks() == ["e1": issue.id])
        links.unlink(eventID: "e1")
        #expect(links.manualLinks().isEmpty)
    }
}
