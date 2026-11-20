import AppIntents
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
private final class FakeControlWriter: ControlWriting {
    private(set) var waterAmounts: [Int?] = []
    private(set) var checkedHabits: [UUID] = []

    func logWater(milliliters: Int?) async -> LocalizedStringResource {
        waterAmounts.append(milliliters)
        return "ok"
    }

    func checkHabit(id: UUID) async -> LocalizedStringResource {
        checkedHabits.append(id)
        return "ok"
    }
}

@MainActor
private final class FakeFocusSwitch: ControlFocusSwitching {
    private(set) var requests: [Bool] = []

    func setRunning(_ on: Bool) async -> Bool {
        requests.append(on)
        return true
    }
}

@MainActor
private final class FakeRouteOpener: ControlRouteOpening {
    private(set) var routes: [AppRoute] = []

    func openControlRoute(_ route: AppRoute) {
        routes.append(route)
    }
}

/// The bridge is a process-wide static, so everything that touches it runs one test at a time.
@MainActor
@Suite(.serialized)
struct ControlActionBridgeTests {
    private let writer = FakeControlWriter()
    private let focus = FakeFocusSwitch()
    private let opener = FakeRouteOpener()

    private var router: ControlActionRouter { ControlActionRouter(writer: writer, focus: focus, router: opener) }

    @Test func logWater_callsServices() async {
        await router.handle(.logWater(milliliters: 250))
        await router.handle(.logWater(milliliters: 250))
        // Two taps are two entries, on purpose.
        #expect(writer.waterAmounts == [250, 250])
    }

    @Test func checkHabit_callsServices() async {
        let id = UUID()
        await router.handle(.checkHabit(id: id))
        #expect(writer.checkedHabits == [id])
    }

    @Test func setFocusTrue_startsFreeSession() async {
        await router.handle(.setFocus(true))
        #expect(focus.requests == [true])
    }

    @Test func setFocusFalse_stopsSession() async {
        await router.handle(.setFocus(false))
        #expect(focus.requests == [false])
    }

    @Test func open_handsTheRouteToTheRouter() async {
        await router.handle(.open(.shopping))
        #expect(opener.routes == [.shopping])
        #expect(writer.waterAmounts.isEmpty && writer.checkedHabits.isEmpty && focus.requests.isEmpty)
    }

    @Test func openIntent_reachesTheRouterThroughTheBridge() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        router.install()
        for route in ControlOpenIntent.allowedRoutes { _ = try await ControlOpenIntent(route: route).perform() }
        #expect(opener.routes == [.capture, .routineNow, .shopping, .notesDictate])
    }

    @Test func openIntent_ignoresRoutesOutsideTheAllowlist() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        router.install()
        _ = try await ControlOpenIntent(route: .routineWeek).perform()
        let unknown = ControlOpenIntent()
        unknown.route = "not/a/route"
        _ = try await unknown.perform()
        #expect(opener.routes.isEmpty)
    }

    @Test func openIntent_opensTheAppInTheForeground() {
        // The point of the fix: a control that opens the app needs a foreground intent, not an `OpenURLIntent`.
        #expect(ControlOpenIntent.supportedModes == .foreground(.immediate))
    }

    @Test func openIntent_forRoutineNow_isResolvedByTheRealRouterAtShowTime() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        let appRouter = AppRouter(now: { Date(timeIntervalSince1970: 1_800_000_000) }, calendar: .tagwerk)
        ControlActionRouter(writer: writer, focus: focus, router: appRouter).install()
        _ = try await ControlOpenIntent(route: .routineNow).perform()
        let request = appRouter.takeRequest(setupCompleted: true)
        #expect(request.map { [.routineStart, .routineEvening].contains($0.route) } == true)
    }

    @Test func openIntent_forDictation_setsTheDictationRequest() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        let appRouter = AppRouter()
        ControlActionRouter(writer: writer, focus: focus, router: appRouter).install()
        _ = try await ControlOpenIntent(route: .notesDictate).perform()
        #expect(appRouter.takeRequest(setupCompleted: true)?.route == .notesDictate)
        #expect(appRouter.takeDictationRequest())
    }

    @Test func openIntent_beforeSetup_staysBufferedUntilSetupIsDone() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        let appRouter = AppRouter()
        ControlActionRouter(writer: writer, focus: focus, router: appRouter).install()
        _ = try await ControlOpenIntent(route: .shopping).perform()
        #expect(appRouter.takeRequest(setupCompleted: false) == nil)
        #expect(appRouter.takeRequest(setupCompleted: true)?.route == .shopping)
    }

    @Test func missingHandler_doesNothing() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        ControlActionBridge.handler = nil
        // In the widget extension no handler is set; the intents must not fail or crash.
        _ = try await ControlLogWaterIntent(milliliters: 250).perform()
        _ = try await ControlCheckHabitIntent(habit: nil).perform()
        let focusIntent = ControlSetFocusIntent()
        focusIntent.value = true
        _ = try await focusIntent.perform()
        _ = try await ControlOpenIntent(route: .shopping).perform()
        #expect(writer.waterAmounts.isEmpty && focus.requests.isEmpty && opener.routes.isEmpty)
    }

    @Test func installedRouter_receivesTheIntents() async throws {
        let saved = ControlActionBridge.handler
        defer { ControlActionBridge.handler = saved }
        router.install()
        _ = try await ControlLogWaterIntent(milliliters: 500).perform()
        let focusIntent = ControlSetFocusIntent()
        focusIntent.value = true
        _ = try await focusIntent.perform()
        let habitID = UUID()
        _ = try await ControlCheckHabitIntent(habit: HabitEntity(ControlHabit(id: habitID, name: "Lesen", symbol: "book"))).perform()
        #expect(writer.waterAmounts == [500])
        #expect(focus.requests == [true])
        #expect(writer.checkedHabits == [habitID])
    }

    @Test func handlerIsInstalledAtLaunch() {
        // `TagwerkApp.init` runs in the test host; a control tap that starts the app must find the handler there.
        #expect(ControlActionBridge.handler != nil)
    }
}
