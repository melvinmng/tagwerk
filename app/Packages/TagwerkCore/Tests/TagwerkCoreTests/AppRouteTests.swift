import Foundation
import Testing
@testable import TagwerkCore

struct AppRouteTests {
    @Test func route_parsesKnownPaths() {
        #expect(AppRoute(url: URL(string: "tagwerk://plan/today")!) == .planToday)
        #expect(AppRoute(url: URL(string: "tagwerk://capture")!) == .capture)
        #expect(AppRoute(url: URL(string: "tagwerk://capture/meal")!) == .captureMeal)
        #expect(AppRoute(url: URL(string: "tagwerk://capture/workout")!) == .captureWorkout)
        #expect(AppRoute(url: URL(string: "tagwerk://review")!) == .review)
    }

    @Test func route_rejectsUnknownSchemeHostAndPath() {
        #expect(AppRoute(url: URL(string: "https://plan/today")!) == nil)
        #expect(AppRoute(url: URL(string: "tagwerk://settings")!) == nil)
        #expect(AppRoute(url: URL(string: "tagwerk://capture/water")!) == nil)
        #expect(AppRoute(url: URL(string: "tagwerk://plan")!) == nil)
    }

    @Test func route_ignoresQueryParameters() {
        #expect(AppRoute(url: URL(string: "tagwerk://capture/meal?text=Pizza&estimate=1")!) == .captureMeal)
    }

    @Test func route_roundTripsURL() {
        for route in AppRoute.allCases {
            #expect(AppRoute(url: route.url) == route)
        }
    }

    @Test func route_parsesShopping_andIgnoresParameters() {
        #expect(AppRoute(url: URL(string: "tagwerk://shopping")!) == .shopping)
        #expect(AppRoute(url: URL(string: "tagwerk://shopping?add=Bier")!) == .shopping)
        #expect(AppRoute.shopping.url.absoluteString == "tagwerk://shopping")
        #expect(AppRoute(url: URL(string: "tagwerk://shopping/add")!) == nil)
    }
}
