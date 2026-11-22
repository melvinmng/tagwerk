import Testing
@testable import TagwerkCore

struct LeftoverPreviewTests {
    @Test func fit_fits() {
        #expect(LeftoverPreview.fit(neededMinutes: 150, freeMinutes: 240, isDayOff: false) == .fits(freeMinutes: 240))
        // Exactly as much as needed still fits.
        #expect(LeftoverPreview.fit(neededMinutes: 150, freeMinutes: 150, isDayOff: false) == .fits(freeMinutes: 150))
    }

    @Test func fit_tight() {
        #expect(LeftoverPreview.fit(neededMinutes: 150, freeMinutes: 90, isDayOff: false) == .tight(freeMinutes: 90, neededMinutes: 150))
        // An overbooked day has no free time at all.
        #expect(LeftoverPreview.fit(neededMinutes: 30, freeMinutes: -20, isDayOff: false) == .tight(freeMinutes: 0, neededMinutes: 30))
    }

    @Test func fit_dayOff() {
        #expect(LeftoverPreview.fit(neededMinutes: 30, freeMinutes: 480, isDayOff: true) == .dayOff)
    }

    @Test func fit_withoutCapacity_isUnknown() {
        #expect(LeftoverPreview.fit(neededMinutes: 30, freeMinutes: nil, isDayOff: false) == .unknown)
    }

    @Test func showsLeftoverLine_noTasks_false() {
        #expect(!LeftoverPreview.showsLeftoverLine(leftoverCount: 0, isOverCapacity: true, minutesOfDay: 17 * 60, workdayEndMinutes: 18 * 60))
    }

    @Test func showsLeftoverLine_overCapacity_true() {
        #expect(LeftoverPreview.showsLeftoverLine(leftoverCount: 2, isOverCapacity: true, minutesOfDay: 9 * 60, workdayEndMinutes: 18 * 60))
    }

    @Test func showsLeftoverLine_lateAfternoon_true() {
        // From two hours before the end of work on: 16:00 for a day that ends at 18:00.
        #expect(LeftoverPreview.showsLeftoverLine(leftoverCount: 1, isOverCapacity: false, minutesOfDay: 16 * 60, workdayEndMinutes: 18 * 60))
        #expect(LeftoverPreview.showsLeftoverLine(leftoverCount: 1, isOverCapacity: false, minutesOfDay: 19 * 60, workdayEndMinutes: 18 * 60))
    }

    @Test func showsLeftoverLine_morningWithinCapacity_false() {
        #expect(!LeftoverPreview.showsLeftoverLine(leftoverCount: 3, isOverCapacity: false, minutesOfDay: 9 * 60, workdayEndMinutes: 18 * 60))
        #expect(!LeftoverPreview.showsLeftoverLine(leftoverCount: 3, isOverCapacity: false, minutesOfDay: 16 * 60 - 1, workdayEndMinutes: 18 * 60))
    }
}
