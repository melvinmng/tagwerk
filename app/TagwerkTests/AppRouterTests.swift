import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct AppRouterTests {
    @Test func router_buffersUntilSetupCompleted() {
        let router = AppRouter()
        #expect(router.open(URL(string: "tagwerk://capture")!))
        #expect(router.takeRequest(setupCompleted: false) == nil)
        #expect(router.takeRequest(setupCompleted: true)?.route == .capture)
        #expect(router.takeRequest(setupCompleted: true) == nil)
    }

    @Test func router_mealPrefill_consumedOnce() {
        let router = AppRouter()
        router.open(.captureMeal, prefill: .meal(text: "Zwei Brötchen"))
        _ = router.takeRequest(setupCompleted: true)
        #expect(router.takeCapturePrefill() == .meal(text: "Zwei Brötchen"))
        #expect(router.takeCapturePrefill() == nil)
    }

    @Test func router_linkWithoutPrefill_usesRouteDefault() {
        let router = AppRouter()
        router.open(URL(string: "tagwerk://capture/workout?minutes=999")!)
        _ = router.takeRequest(setupCompleted: true)
        #expect(router.takeCapturePrefill() == .workout(activity: nil, minutes: nil))
    }

    @Test func router_captureLink_showsToday() {
        let router = AppRouter()
        router.open(URL(string: "tagwerk://capture")!)
        _ = router.takeRequest(setupCompleted: true)
        #expect(router.takeCapturePrefill() == .today)
    }

    @Test func router_unknownURL_ignored() {
        let router = AppRouter()
        #expect(router.open(URL(string: "tagwerk://capture/water?ml=250")!) == false)
        #expect(router.receivedCount == 0)
        #expect(router.takeRequest(setupCompleted: true) == nil)
    }

    @Test func router_secondRequestReplacesFirst() {
        let router = AppRouter()
        router.open(.capture)
        router.open(.planToday)
        #expect(router.receivedCount == 2)
        #expect(router.takeRequest(setupCompleted: true)?.route == .planToday)
    }

    @Test func router_shoppingLink_hasNoPrefill() {
        let router = AppRouter()
        #expect(router.open(URL(string: "tagwerk://shopping?add=Bier")!))
        let request = router.takeRequest(setupCompleted: true)
        #expect(request?.route == .shopping && request?.prefill == nil)
        #expect(router.takeCapturePrefill() == nil)
    }

    @Test func router_routineRoutes_haveNoPrefill() {
        let router = AppRouter()
        router.open(URL(string: "tagwerk://routine/evening")!)
        #expect(router.takeRequest(setupCompleted: true) == AppRouter.Request(route: .routineEvening, prefill: nil))
        #expect(router.takeCapturePrefill() == nil)
        router.open(.routineStart)
        #expect(router.takeRequest(setupCompleted: true)?.route == .routineStart)
        #expect(router.takeCapturePrefill() == nil)
    }

    private func router(atHour hour: Int, minute: Int = 0) -> AppRouter {
        let calendar = Calendar(identifier: .gregorian)
        let moment = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: hour, minute: minute))!
        return AppRouter(now: { moment }, calendar: calendar)
    }

    @Test func bibleStudyStart_opensStartSheet() {
        let router = router(atHour: 8)
        #expect(router.open(URL(string: "tagwerk://bible/start")!))
        #expect(router.bibleStudyStartRequested == false, "the request is buffered until it is shown")
        #expect(router.takeRequest(setupCompleted: true)?.route == .bibleStudyStart)
        #expect(router.bibleStudyStartRequested)
        #expect(router.takeBibleStudyStartRequest())
        #expect(!router.takeBibleStudyStartRequest(), "the sheet opens once")
        router.open(.routineStart)
        _ = router.takeRequest(setupCompleted: true)
        #expect(!router.bibleStudyStartRequested)
    }

    @Test func routineNow_morning_opensStart() {
        let router = router(atHour: 8)
        #expect(router.open(URL(string: "tagwerk://routine/now")!))
        #expect(router.takeRequest(setupCompleted: true)?.route == .routineStart)
    }

    @Test func routineNow_evening_opensEvening() {
        let router = router(atHour: 21)
        router.open(.routineNow)
        #expect(router.takeRequest(setupCompleted: true)?.route == .routineEvening)
    }

    @Test func routineNow_after_midnight_opensEvening() {
        let router = router(atHour: 0, minute: 30)
        router.open(.routineNow)
        #expect(router.takeRequest(setupCompleted: true)?.route == .routineEvening)
    }

    @Test func routineNow_resolvedWhenShown_notWhenReceived() {
        // The request waits for the setup; the time of day counts when it is shown.
        let calendar = Calendar(identifier: .gregorian)
        var moment = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 11, minute: 59))!
        let router = AppRouter(now: { moment }, calendar: calendar)
        router.open(.routineNow)
        moment = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12, minute: 1))!
        #expect(router.takeRequest(setupCompleted: true)?.route == .routineEvening)
    }

    @Test func notesDictate_setsDictationRequest() {
        let router = AppRouter()
        #expect(router.open(URL(string: "tagwerk://notes/dictate")!))
        #expect(router.dictationRequested == false)  // only once the request is shown
        #expect(router.takeRequest(setupCompleted: true)?.route == .notesDictate)
        #expect(router.takeCapturePrefill() == nil)
        #expect(router.takeDictationRequest() == true)
        #expect(router.takeDictationRequest() == false)
    }

    @Test func otherRoutes_doNotRequestDictation() {
        let router = AppRouter()
        router.open(.notesDictate)
        _ = router.takeRequest(setupCompleted: true)
        router.open(.capture)
        _ = router.takeRequest(setupCompleted: true)
        #expect(router.takeDictationRequest() == false)
    }
}
