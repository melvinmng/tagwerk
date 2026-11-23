import Testing
import UIKit
@testable import Tagwerk

/// The colour of the bolt and the progress ring of automatic habits (GW3b): present in both appearances and at least 3:1 against
/// the list backgrounds, because both are graphic objects (WCAG 1.4.11).
struct HabitMarkerTintTests {
    @Test func asset_resolvesInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            #expect(ContrastMath.color(named: HabitMarkerTint.assetName, style: style) != nil, "missing for style \(style.rawValue)")
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func markerColour_hasThreeToOneAgainstTheListBackgrounds(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let backgrounds = [UIColor.systemGroupedBackground, UIColor.secondarySystemGroupedBackground, UIColor.systemBackground]
            .map { $0.resolvedColor(with: traits) }
        let colour = try #require(ContrastMath.color(named: HabitMarkerTint.assetName, style: style))
        for background in backgrounds {
            let ratio = ContrastMath.ratio(colour, background)
            #expect(ratio >= 3, "\(HabitMarkerTint.assetName) has \(ratio):1 in style \(style.rawValue)")
        }
    }
}
