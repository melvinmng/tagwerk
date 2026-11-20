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

/// The bridge is a process-wide static, so everything that touches it runs one test at a time.
@MainActor
@Suite(.serialized)
struct ControlActionBridgeTests {
    private let writer = FakeControlWriter()
    private let focus = FakeFocusSwitch()

    private var router: ControlActionRouter { ControlActionRouter(writer: writer, focus: focus) }

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
        #expect(writer.waterAmounts.isEmpty && focus.requests.isEmpty)
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
