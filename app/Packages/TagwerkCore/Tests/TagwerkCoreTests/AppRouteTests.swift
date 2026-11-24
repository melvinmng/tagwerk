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

    @Test func appRoute_routineWeek_roundTrips() {
        #expect(AppRoute(url: URL(string: "tagwerk://routine/week")!) == .routineWeek)
        #expect(AppRoute.routineWeek.url.absoluteString == "tagwerk://routine/week")
        #expect(AppRoute(url: AppRoute.routineWeek.url) == .routineWeek)
    }

    @Test func route_parsesRoutinePaths() {
        #expect(AppRoute(url: URL(string: "tagwerk://routine/start")!) == .routineStart)
        #expect(AppRoute(url: URL(string: "tagwerk://routine/evening")!) == .routineEvening)
        #expect(AppRoute(url: URL(string: "tagwerk://routine/abend")!) == nil)
    }

    @Test func parses_notesDictate() {
        #expect(AppRoute(url: URL(string: "tagwerk://notes/dictate")!) == .notesDictate)
        #expect(AppRoute.notesDictate.url.absoluteString == "tagwerk://notes/dictate")
        #expect(AppRoute(url: URL(string: "tagwerk://notes")!) == nil)
    }

    @Test func parses_bibleStudyStart() {
        #expect(AppRoute(url: URL(string: "tagwerk://bible/start")!) == .bibleStudyStart)
        #expect(AppRoute.bibleStudyStart.url.absoluteString == "tagwerk://bible/start")
        #expect(AppRoute(url: URL(string: "tagwerk://bible")!) == nil)
    }

    @Test func parses_routineNow() {
        #expect(AppRoute(url: URL(string: "tagwerk://routine/now")!) == .routineNow)
        #expect(AppRoute.routineNow.url.absoluteString == "tagwerk://routine/now")
    }

    @Test func allCases_roundTripURL() {
        for route in AppRoute.allCases {
            #expect(AppRoute(url: route.url) == route)
        }
        #expect(Set(AppRoute.allCases.map(\.rawValue)).count == AppRoute.allCases.count)
    }
}
