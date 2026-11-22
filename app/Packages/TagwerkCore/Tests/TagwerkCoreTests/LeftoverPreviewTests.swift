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
}
