import SwiftUI
import Testing
import UIKit
@testable import Tagwerk

struct MarkerColorsTests {
    private static let assetNames = ["NowMarkerFill", "OnNowMarker", "TravelWarningFill", "OnTravelWarning"]
    private static let appearances: [UIUserInterfaceStyle] = [.light, .dark]

    @Test func allAssets_resolveInBothAppearances() {
        for name in Self.assetNames {
            for style in Self.appearances {
                #expect(ContrastMath.color(named: name, style: style) != nil, "\(name) is missing for style \(style.rawValue)")
            }
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func nowMarker_whiteOnFill_isAtLeast4_5(style: UIUserInterfaceStyle) throws {
        let fill = try #require(ContrastMath.color(named: "NowMarkerFill", style: style))
        let text = try #require(ContrastMath.color(named: "OnNowMarker", style: style))
        let ratio = ContrastMath.ratio(text, fill)
        #expect(ratio >= 4.5, "now marker contrast \(ratio) in style \(style.rawValue)")
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func travelWarning_textOnFill_isAtLeast4_5(style: UIUserInterfaceStyle) throws {
        let fill = try #require(ContrastMath.color(named: "TravelWarningFill", style: style))
        let text = try #require(ContrastMath.color(named: "OnTravelWarning", style: style))
        let ratio = ContrastMath.ratio(text, fill)
        #expect(ratio >= 4.5, "travel warning contrast \(ratio) in style \(style.rawValue)")
    }

    @Test func contrastMath_knownPairs() {
        #expect(abs(ContrastMath.ratio(.black, .white) - 21) < 0.01)
        let grey = UIColor(red: 0x76 / 255, green: 0x76 / 255, blue: 0x76 / 255, alpha: 1)
        #expect(abs(ContrastMath.ratio(grey, .white) - 4.54) < 0.01)
    }

    @Test func markerColorExtension_usesTheCatalogNames() {
        // The extension only wraps catalog names; a wrong name would render as clear and fail the measurement tests.
        #expect(Color.nowMarkerFill == Color("NowMarkerFill"))
        #expect(Color.onNowMarker == Color("OnNowMarker"))
        #expect(Color.travelWarningFill == Color("TravelWarningFill"))
        #expect(Color.onTravelWarning == Color("OnTravelWarning"))
    }
}
