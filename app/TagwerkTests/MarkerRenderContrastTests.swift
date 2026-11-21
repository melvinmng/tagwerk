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
}
