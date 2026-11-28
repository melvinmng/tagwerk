import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct CapacityTextTests {
    private func clock(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }

    private func capacity(busy: [Range<Int>] = [], travel: [Range<Int>] = [], blocks: [Range<Int>] = [], untimed: Int = 0,
                          lunch: Bool = true) -> DayCapacity {
        TagwerkCore.capacity(CapacityInput(hours: WorkHours(startMinutes: 540, endMinutes: 1080), lunchStartMinutes: 720,
                                           lunchMinutes: lunch ? 60 : 0, bufferMinutes: 10, busyIntervals: busy,
                                           untimedPlannedMinutes: untimed, estimatedCount: 0, travelIntervals: travel,
                                           blockIntervals: blocks))
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
}
