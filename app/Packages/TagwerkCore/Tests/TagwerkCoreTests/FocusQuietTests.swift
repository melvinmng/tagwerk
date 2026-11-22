import Foundation
import Testing
@testable import TagwerkCore

struct FocusQuietTests {
    let calendar = makeCalendar()
    let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { instant(2026, 11, day, hour, minute, in: calendar) }

    // MARK: State

    @Test func start_remembersTheMoment_andKeepsItOnRepeat() {
        let started = FocusQuiet.applying(active: true, now: at(18, 20), to: FocusQuiet.State())
        #expect(started == FocusQuiet.State(since: at(18, 20), catchUpFrom: nil))
        #expect(FocusQuiet.applying(active: true, now: at(18, 21), to: started) == started)
    }

    @Test func end_handsTheStartOverToTheCatchUp() {
        let started = FocusQuiet.State(since: at(18, 20))
        let ended = FocusQuiet.applying(active: false, now: at(18, 22), to: started)
        #expect(ended == FocusQuiet.State(since: nil, catchUpFrom: at(18, 20), catchUpAt: nil))
    }

    @Test func endWithoutStart_changesNothing() {
        #expect(FocusQuiet.applying(active: false, now: at(18, 22), to: FocusQuiet.State()) == FocusQuiet.State())
    }

    @Test func secondFocusBeforeTheCatchUp_keepsTheEarlierStart() {
        let pending = FocusQuiet.State(since: nil, catchUpFrom: at(18, 10))
        let restarted = FocusQuiet.applying(active: true, now: at(18, 12), to: pending)
        let ended = FocusQuiet.applying(active: false, now: at(18, 13), to: restarted)
        #expect(ended.catchUpFrom == at(18, 10))
    }

    @Test func staleStart_isDroppedWithoutCatchUp() {
        let old = FocusQuiet.State(since: at(16, 20))
        let ended = FocusQuiet.applying(active: false, now: at(18, 22), to: old)
        #expect(ended == FocusQuiet.State())
        #expect(FocusQuiet.dropping(staleIn: old, now: at(18, 22)) == FocusQuiet.State())
        #expect(FocusQuiet.dropping(staleIn: FocusQuiet.State(since: at(18, 20)), now: at(18, 22)).since == at(18, 20))
    }

    // MARK: Catch-up

    @Test func scheduling_firstRunAfterTheEnd_picksAMinuteAhead_andLaterRunsKeepIt() {
        let ended = FocusQuiet.State(since: nil, catchUpFrom: at(18, 20))
        let first = FocusQuiet.scheduling(ended, now: at(18, 22))
        #expect(first.catchUp == FocusCatchUp(from: at(18, 20), at: at(18, 22, 1)))
        #expect(first.state.catchUpAt == at(18, 22, 1))
        let second = FocusQuiet.scheduling(first.state, now: at(18, 22).addingTimeInterval(30))
        #expect(second.catchUp == first.catchUp)
    }

    @Test func scheduling_afterTheMomentHasPassed_endsTheCatchUp() {
        let state = FocusQuiet.State(since: nil, catchUpFrom: at(18, 20), catchUpAt: at(18, 22, 1))
        let result = FocusQuiet.scheduling(state, now: at(18, 22, 2))
        #expect(result.catchUp == nil)
        #expect(result.state == FocusQuiet.State())
    }

    @Test func scheduling_whileFocusIsActive_waits() {
        let state = FocusQuiet.State(since: at(18, 21), catchUpFrom: at(18, 10))
        let result = FocusQuiet.scheduling(state, now: at(18, 22))
        #expect(result.catchUp == nil)
        #expect(result.state == state)
    }

    @Test func scheduling_withoutAnything_changesNothing() {
        let result = FocusQuiet.scheduling(FocusQuiet.State(), now: at(18, 22))
        #expect(result.catchUp == nil)
        #expect(result.state == FocusQuiet.State())
    }

    @Test func applying_endBeforeTheTarget_startsTheCatchUp() {
        let started = FocusQuiet.State(since: at(18, 14))
        let ended = FocusQuiet.applying(active: false, now: at(18, 17), to: started, quietHours: night, calendar: calendar)
        #expect(ended == FocusQuiet.State(since: nil, catchUpFrom: at(18, 14), catchUpAt: nil))
    }

    @Test func applying_endAfterTheTarget_startsNoCatchUp() {
        // Held until 13:00 (four hours after 09:00); the end reported at 17:00 finds everything delivered.
        let started = FocusQuiet.State(since: at(18, 9))
        let ended = FocusQuiet.applying(active: false, now: at(18, 17), to: started, quietHours: night, calendar: calendar)
        #expect(ended == FocusQuiet.State())
        // The target itself counts as passed.
        let atTarget = FocusQuiet.applying(active: false, now: at(18, 13), to: started, quietHours: night, calendar: calendar)
        #expect(atTarget == FocusQuiet.State())
    }

    @Test func applying_endAfterTheTarget_withoutQuietHours_usesEightHours() {
        let started = FocusQuiet.State(since: at(18, 9))
        let early = FocusQuiet.applying(active: false, now: at(18, 16), to: started, quietHours: nil, calendar: calendar)
        #expect(early.catchUpFrom == at(18, 9))
        let late = FocusQuiet.applying(active: false, now: at(18, 17), to: started, quietHours: nil, calendar: calendar)
        #expect(late == FocusQuiet.State())
    }

    @Test func applying_endAfterTheTarget_keepsAnEarlierPendingCatchUp() {
        let started = FocusQuiet.State(since: at(18, 12), catchUpFrom: at(18, 8))
        let ended = FocusQuiet.applying(active: false, now: at(18, 20), to: started, quietHours: nil, calendar: calendar)
        #expect(ended == FocusQuiet.State(since: nil, catchUpFrom: at(18, 8), catchUpAt: nil))
    }

    // MARK: Fallback target

    @Test func fallbackTarget_fourHoursAfterTheStart() {
        #expect(FocusQuiet.fallbackTarget(since: at(18, 14), quietHours: night, calendar: calendar) == at(18, 18))
    }

    @Test func fallbackTarget_insideQuietHours_movesToTheirEnd() {
        #expect(FocusQuiet.fallbackTarget(since: at(18, 21, 30), quietHours: night, calendar: calendar) == at(19, 7))
        // Exactly at the start of the window counts as inside.
        #expect(FocusQuiet.fallbackTarget(since: at(18, 19), quietHours: night, calendar: calendar) == at(19, 7))
    }

    @Test func fallbackTarget_withoutQuietHours_isEightHours() {
        #expect(FocusQuiet.fallbackTarget(since: at(18, 13), quietHours: nil, calendar: calendar) == at(18, 21))
        let empty = QuietHours(startMinutes: 300, endMinutes: 300)
        #expect(FocusQuiet.fallbackTarget(since: at(18, 13), quietHours: empty, calendar: calendar) == at(18, 21))
    }

    // MARK: Hold

    @Test func hold_withQuietHours_endsWithTheRunningWindow() {
        let hold = FocusQuiet.hold(since: at(18, 23, 30), now: at(19, 0, 10), quietHours: night, calendar: calendar)
        #expect(hold == FocusHold(from: at(18, 23, 30), until: at(19, 7)))
    }

    @Test func hold_endsAtTheFallbackTarget() {
        let hold = FocusQuiet.hold(since: at(18, 13), now: at(18, 14), quietHours: night, calendar: calendar)
        #expect(hold == FocusHold(from: at(18, 13), until: at(18, 17)))
        #expect(FocusQuiet.hold(since: at(18, 13), now: at(18, 17), quietHours: night, calendar: calendar) == nil)
    }

    @Test func hold_withoutQuietHours_lastsEightHoursFromTheStart() {
        let hold = FocusQuiet.hold(since: at(18, 13), now: at(18, 14), quietHours: nil, calendar: calendar)
        #expect(hold == FocusHold(from: at(18, 13), until: at(18, 21)))
        #expect(FocusQuiet.hold(since: at(18, 13), now: at(18, 21), quietHours: nil, calendar: calendar) == nil)
    }

    @Test func hold_inactiveOrStale_isNil() {
        #expect(FocusQuiet.hold(since: nil, now: at(18, 14), quietHours: night, calendar: calendar) == nil)
        #expect(FocusQuiet.hold(since: at(17, 13), now: at(18, 14), quietHours: night, calendar: calendar) == nil)
    }

    @Test func hold_emptyQuietHours_actLikeNone() {
        let empty = QuietHours(startMinutes: 300, endMinutes: 300)
        let hold = FocusQuiet.hold(since: at(18, 13), now: at(18, 14), quietHours: empty, calendar: calendar)
        #expect(hold?.until == at(18, 21))
    }
}
