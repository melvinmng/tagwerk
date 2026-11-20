import Foundation
import Testing
@testable import Tagwerk

struct ControlStateTests {
    private func makeState() -> ControlState {
        let suite = "test.controls.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ControlState(defaults: defaults)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func focus_isOffByDefault() {
        #expect(makeState().isFocusOn(at: now) == false)
    }

    @Test func focus_isOnWhileTheProjectedEndLiesAhead() {
        let state = makeState()
        state.writeFocus(isRunning: true, endsAt: now.addingTimeInterval(600))
        #expect(state.isFocusOn(at: now))
        #expect(state.isFocusOn(at: now.addingTimeInterval(599)))
    }

    @Test func focus_isOffOnceTheTimerRanOutInTheBackground() {
        let state = makeState()
        state.writeFocus(isRunning: true, endsAt: now.addingTimeInterval(600))
        #expect(state.isFocusOn(at: now.addingTimeInterval(600)) == false)
        #expect(state.isFocusOn(at: now.addingTimeInterval(3600)) == false)
    }

    @Test func focus_pausedHasNoEnd_andStaysOn() {
        let state = makeState()
        state.writeFocus(isRunning: true, endsAt: nil)
        #expect(state.isFocusOn(at: now.addingTimeInterval(86_400)))
    }

    @Test func focus_stoppedClearsTheEnd() {
        let state = makeState()
        state.writeFocus(isRunning: true, endsAt: now.addingTimeInterval(600))
        state.writeFocus(isRunning: false, endsAt: now.addingTimeInterval(600))
        #expect(state.isFocusOn(at: now) == false)
    }

    @Test func writeFocus_reportsChangesOnly() {
        let state = makeState()
        #expect(state.writeFocus(isRunning: true, endsAt: now.addingTimeInterval(600)))
        #expect(state.writeFocus(isRunning: true, endsAt: now.addingTimeInterval(600)) == false)
        #expect(state.writeFocus(isRunning: true, endsAt: nil))
        #expect(state.writeFocus(isRunning: false, endsAt: nil))
        #expect(state.writeFocus(isRunning: false, endsAt: nil) == false)
    }

    @Test func habits_roundTrip_namesAndSymbolsOnly() throws {
        let state = makeState()
        let habit = ControlHabit(id: UUID(), name: "Lesen", symbol: "book")
        state.writeHabits([habit])
        #expect(state.habits() == [habit])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state.habits())) as? [[String: Any]]
        #expect(Set(object?.first?.keys.map { $0 } ?? []) == ["id", "name", "symbol"])
    }

    @Test func live_withoutAGroupInTheBundle_isNil() {
        // The test bundle has no App Group entry in its Info.plist.
        #expect(ControlState.live(bundle: Bundle(for: BundleToken.self)) == nil)
    }
}

private final class BundleToken {}
