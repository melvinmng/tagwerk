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
}
