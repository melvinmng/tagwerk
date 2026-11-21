import SwiftUI
import Testing
@testable import Tagwerk

/// Contrast measured on the rendered image of a marker (the fill against the glyph pixels), next to the computed
/// values of `MarkerColorsTests` and the accessibility audit (PL1b).
@MainActor
struct MarkerRenderContrastTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func nowCapsule_renderedContrast(scheme: ColorScheme) throws {
        let ratio = try #require(ContrastMath.renderedRatio(of: NowTimeCapsule(time: "14:32"), colorScheme: scheme))
        // Recorded for the pull request description: a passing expectation prints nothing.
        print("MEASURED now capsule \(scheme == .dark ? "dark" : "light"): \(String(format: "%.2f", ratio)):1")
        #expect(ratio >= 4.5, "rendered contrast of the time capsule is \(ratio)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func nowCapsule_withRowTitle_renderedContrast(scheme: ColorScheme) throws {
        let ratio = try #require(ContrastMath.renderedRatio(of: NowTimeCapsule(time: NowText.rowTitle(time: "14:32")),
                                                            colorScheme: scheme))
        print("MEASURED now row capsule \(scheme == .dark ? "dark" : "light"): \(String(format: "%.2f", ratio)):1")
        #expect(ratio >= 4.5, "rendered contrast of the row capsule is \(ratio)")
    }

    /// The block of collapsed entries (BF1c) puts primary text on grey at 24 %. The accessibility audit reports its headline
    /// as a contrast finding in the AX5 run; this measures the rendered image instead (on the app background).
    @Test(arguments: [ColorScheme.light, .dark])
    func collapsedBlock_renderedContrast(scheme: ColorScheme) throws {
        let block = CollapsedGroupBlock(count: 3, timeText: "10:00–12:30", startText: "10:00", endText: "12:30",
                                        titles: ["Seminar", "Seminar", "Abgabe Kurzbericht"], hasDeadline: false,
                                        isRunning: false, height: 90) {}
            .frame(width: 280, height: 90)
            .background(.background)
        let ratio = try #require(ContrastMath.renderedRatio(of: block, colorScheme: scheme))
        print("MEASURED collapsed block \(scheme == .dark ? "dark" : "light"): \(String(format: "%.2f", ratio)):1")
        #expect(ratio >= 4.5, "rendered contrast of the collapsed block is \(ratio)")
    }

    /// The capsule "10 min zu früh" of a tight trip (PL10b), measured on the rendered image; one of the four proofs that
    /// decide between the capsule and the text mark PL10a (plan g1, V2).
    private func travelCapsuleRatio(_ scheme: ColorScheme) throws -> Double {
        let ratio = try #require(ContrastMath.renderedRatio(of: TravelWarningCapsule(minutes: 10), colorScheme: scheme))
        print("MEASURED travel capsule \(scheme == .dark ? "dark" : "light"): \(String(format: "%.2f", ratio)):1")
        return ratio
    }

    @Test func travelCapsule_renderedContrast_light() throws {
        let ratio = try travelCapsuleRatio(.light)
        #expect(ratio >= 4.5, "rendered contrast of the travel capsule (light) is \(ratio)")
    }

    @Test func travelCapsule_renderedContrast_dark() throws {
        let ratio = try travelCapsuleRatio(.dark)
        #expect(ratio >= 4.5, "rendered contrast of the travel capsule (dark) is \(ratio)")
    }
}
