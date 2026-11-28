import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct CapacityTextTests {
    private func clock(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }

    private func capacity(busy: [Range<Int>] = [], travel: [Range<Int>] = [], blocks: [Range<Int>] = [], untimed: Int = 0,
                          count: Int = 0, estimated: Int = 0, lunch: Bool = true, now: Int? = nil,
                          dayOff: Bool = false) -> DayCapacity {
        var input = CapacityInput(hours: dayOff ? nil : WorkHours(startMinutes: 540, endMinutes: 1080), lunchStartMinutes: 720,
                                  lunchMinutes: lunch ? 60 : 0, bufferMinutes: 10, busyIntervals: busy,
                                  untimedPlannedMinutes: untimed, estimatedCount: estimated, travelIntervals: travel,
                                  blockIntervals: blocks, untimedCount: count)
        input.nowMinutes = now
        return TagwerkCore.capacity(input)
    }

    /// The day of the 28 Nov report: appointment 12:00–14:00, lunch, six tasks without effort and without a time block.
    private func reportedDay(now: Int? = nil) -> DayCapacity {
        capacity(busy: [720..<840], untimed: 180, count: 6, estimated: 6, now: now)
    }

    private func line(_ value: DayCapacity) -> String? {
        CapacityText.explanation(value, hours: WorkHours(startMinutes: 540, endMinutes: 1080), clock: clock)
    }

    @Test func explanation_reportedDay_namesWindowAndLunch() {
        #expect(line(capacity(busy: [720..<780])) == "9:00–18:00 · 1 h Pause")
    }

    @Test func explanation_namesEveryDeduction() {
        // Event 10:00–11:00 with buffer 80 min, trip 30 min, block 14:00–15:00; 30 min of tasks without a time are no deduction.
        let value = capacity(busy: [600..<660], travel: [840..<870], blocks: [900..<960], untimed: 30)
        #expect(line(value) == "9:00–18:00 · 1 h Pause · 1 h 20 Termine · 30 min Fahrzeit · 1 h eingeplant")
    }

    @Test func explanation_leavesOutPartsWithoutMinutes() {
        #expect(line(capacity(lunch: false)) == "9:00–18:00")
        #expect(line(capacity(blocks: [600..<645], lunch: false)) == "9:00–18:00 · 45 min eingeplant")
        // Tasks without a time block are named by the hint, not by the explanation line.
        #expect(line(capacity(untimed: 45, lunch: false)) == "9:00–18:00")
    }

    @Test func explanation_dayOff_hasNoLine() {
        let off = TagwerkCore.capacity(CapacityInput(hours: nil, lunchStartMinutes: 720, lunchMinutes: 60, bufferMinutes: 10,
                                                     busyIntervals: [], untimedPlannedMinutes: 0, estimatedCount: 0))
        #expect(CapacityText.explanation(off, hours: nil, clock: clock) == nil)
    }

    @Test func summary_ofTheReportedDay() {
        #expect(CapacityText.summary(capacity(busy: [720..<780])) == "8 h frei von 8 h")
    }

    // MARK: Tasks without a time block

    @Test func summary_reportedDay_untimedTasksTakeNoFreeTime() {
        #expect(CapacityText.summary(reportedDay(now: 804)) == "6 h 40 frei von 6 h 40")
        #expect(CapacityText.remaining(reportedDay(now: 804)) == "3 h 50 noch frei")
        #expect(CapacityText.explanation(reportedDay(), hours: WorkHours(startMinutes: 540, endMinutes: 1080), clock: clock)
                == "9:00–18:00 · 1 h Pause · 1 h 20 Termine")
    }

    @Test func summary_dayOffWithUntimedTasksOnly_isNoWorkday() {
        let value = capacity(untimed: 90, count: 3, dayOff: true)
        #expect(CapacityText.summary(value) == "kein Arbeitstag")
        #expect(CapacityText.remaining(value) == "kein Arbeitstag")
    }

    @Test func untimedHint_reportedDay_fitsIntoTheTimeStillFree() {
        #expect(CapacityText.untimedHint(reportedDay(now: 804)) == "6 Aufgaben ohne Uhrzeit · 3 h – passen in die noch freie Zeit")
    }

    @Test func untimedHint_today_exceeds() {
        // At 16:00 120 min are still free; 180 min of tasks are 1 h more.
        #expect(CapacityText.untimedHint(reportedDay(now: 960)) == "6 Aufgaben ohne Uhrzeit · 3 h – 1 h mehr als noch frei")
    }

    @Test func untimedHint_futureDay_fitsAndExceeds() {
        #expect(CapacityText.untimedHint(reportedDay()) == "6 Aufgaben ohne Uhrzeit · 3 h – passen in die freie Zeit")
        let tooMuch = capacity(busy: [720..<840], untimed: 450, count: 15)
        #expect(CapacityText.untimedHint(tooMuch) == "15 Aufgaben ohne Uhrzeit · 7 h 30 – 50 min mehr als frei")
    }

    @Test func untimedHint_singular() {
        #expect(CapacityText.untimedHint(capacity(untimed: 30, count: 1)) == "1 Aufgabe ohne Uhrzeit · 30 min – passt in die freie Zeit")
        #expect(CapacityText.untimedHint(capacity(untimed: 30, count: 1, now: 600)) == "1 Aufgabe ohne Uhrzeit · 30 min – passt in die noch freie Zeit")
    }

    @Test func untimedHint_withoutTasks_isNil() {
        #expect(CapacityText.untimedHint(capacity(busy: [720..<840])) == nil)
    }

    @Test func untimedHint_dayOff_namesOnlyTheEffort() {
        #expect(CapacityText.untimedHint(capacity(untimed: 180, count: 6, dayOff: true)) == "6 Aufgaben ohne Uhrzeit · 3 h")
    }

    @Test func estimateNote_namesTheEstimatedTasks() {
        #expect(CapacityText.estimateNote(reportedDay()) == "6 davon ohne Aufwand mit Standarddauer gerechnet")
        #expect(CapacityText.estimateNote(capacity(untimed: 60, count: 2)) == nil)
    }
}
