import SwiftUI
import Testing
import UIKit
@testable import Tagwerk

/// Measures the text tones of strand K (plan g3-system-anbindungen) with the WCAG formula on the app's backgrounds, cards and tinted cards.
/// The values are a calculation; the accessibility audit of the UI tests decides (see the plan, task K5).
struct TextTonesTests {
    private static let toneNames = ["TextSecondary", "TextGridTime", "TextRed", "TextOrange", "TextPurple", "TextGreen", "AccentColor"]
    private static let appearances: [UIUserInterfaceStyle] = [.light, .dark]

    private static func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection { UITraitCollection(userInterfaceStyle: style) }

    private static func system(_ color: UIColor, _ style: UIUserInterfaceStyle) -> UIColor { color.resolvedColor(with: traits(style)) }

    /// A colour that is drawn over a background with its own opacity: the result is the opaque colour the display shows.
    private static func over(_ foreground: UIColor, _ background: UIColor) -> UIColor { ContrastMath.composited(foreground, over: background) }

    private static func tone(_ name: String, _ style: UIUserInterfaceStyle) throws -> UIColor {
        try #require(ContrastMath.color(named: name, style: style), "\(name) is missing for style \(style.rawValue)")
    }

    /// Contrast of a tone that is drawn with its opacity over a background.
    private static func ratio(_ name: String, over background: UIColor, _ style: UIUserInterfaceStyle) throws -> Double {
        ContrastMath.ratio(over(try tone(name, style), background), background)
    }

    @Test func allAssets_resolveInBothAppearances() {
        for name in Self.toneNames {
            for style in Self.appearances {
                #expect(ContrastMath.color(named: name, style: style) != nil, "\(name) is missing for style \(style.rawValue)")
            }
        }
    }

    @Test func extension_usesTheCatalogNames() {
        #expect(Color.secondaryText == Color("TextSecondary"))
        #expect(Color.gridTimeText == Color("TextGridTime"))
        #expect(Color.redText == Color("TextRed"))
        #expect(Color.orangeText == Color("TextOrange"))
        #expect(Color.purpleText == Color("TextPurple"))
        #expect(Color.greenText == Color("TextGreen"))
    }

    // MARK: Secondary text (KO1a)

    @Test func systemSecondaryLabel_inTheLightAppearance_isBelow4_5OnTheGroupedBackground() {
        // Control for the measurement below: the grey the app used before is the reason for the tone (the audit reports it).
        let background = Self.system(.systemGroupedBackground, .light)
        let ratio = ContrastMath.ratio(Self.over(Self.system(.secondaryLabel, .light), background), background)
        #expect(ratio < 4.5, "the system grey measures \(ratio); the new tone is no longer needed if this fails")
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func secondaryText_onBackgroundAndCard_isAtLeast4_5(style: UIUserInterfaceStyle) throws {
        for background in [UIColor.systemBackground, .systemGroupedBackground, .secondarySystemGroupedBackground] {
            let ratio = try Self.ratio("TextSecondary", over: Self.system(background, style), style)
            #expect(ratio >= 4.5, "secondary text on \(background) in style \(style.rawValue): \(ratio)")
        }
    }

    @Test func secondaryText_onRedCardTint_isAtLeast4_5() throws {
        // The red deadline card: the system red at 12 % over the card.
        let card = Self.system(.secondarySystemGroupedBackground, .light)
        let tinted = Self.over(Self.system(.systemRed, .light).withAlphaComponent(0.12), card)
        #expect(ContrastMath.ratio(Self.over(try Self.tone("TextSecondary", .light), tinted), tinted) >= 4.5)
    }

    // MARK: Coloured text (KO2a)

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func colouredText_onCardAndOnItsTint_isAtLeast4_5(style: UIUserInterfaceStyle) throws {
        let pairs: [(tone: String, system: UIColor)] = [
            ("TextRed", .systemRed), ("TextOrange", .systemOrange), ("TextPurple", .systemPurple), ("TextGreen", .systemGreen),
        ]
        let card = Self.system(.secondarySystemGroupedBackground, style)
        let background = Self.system(.systemBackground, style)
        for pair in pairs {
            let tint = Self.over(Self.system(pair.system, style).withAlphaComponent(0.12), card)
            for surface in [card, background, tint] {
                let ratio = try Self.ratio(pair.tone, over: surface, style)
                #expect(ratio >= 4.5, "\(pair.tone) in style \(style.rawValue): \(ratio)")
            }
        }
    }

    // MARK: Accent colour (KO4a)

    @Test func accentColor_whiteOnFill_isAtLeast4_5InTheLightAppearance() throws {
        let accent = try Self.tone("AccentColor", .light)
        #expect(ContrastMath.ratio(.white, accent) >= 4.5)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func accentColor_asTextOnBackgroundAndCard_isAtLeast4_5(style: UIUserInterfaceStyle) throws {
        let accent = try Self.tone("AccentColor", style)
        for background in [UIColor.systemBackground, .systemGroupedBackground, .secondarySystemGroupedBackground] {
            let ratio = ContrastMath.ratio(accent, Self.system(background, style))
            #expect(ratio >= 4.5, "accent on \(background) in style \(style.rawValue): \(ratio)")
        }
    }

    // MARK: Time line in the hour grid (KO3a)

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func gridTimeText_onTheEventTint_isAtLeast4_5(style: UIUserInterfaceStyle) throws {
        // Entries of the grid: the event colour at 24 % over the page background (blue, green, red, grey).
        let page = Self.system(.systemBackground, style)
        for colour in [UIColor.systemBlue, .systemGreen, .systemRed, .systemGray] {
            let tint = Self.over(Self.system(colour, style).withAlphaComponent(0.24), page)
            let ratio = ContrastMath.ratio(Self.over(try Self.tone("TextGridTime", style), tint), tint)
            #expect(ratio >= 4.5, "grid time on \(colour) in style \(style.rawValue): \(ratio)")
        }
    }
}
