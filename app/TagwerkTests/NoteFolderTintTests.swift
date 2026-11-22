import SwiftUI
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

/// The folder colours of the notes entry page (NO2b): present in both appearances and at least 3:1 against the list
/// backgrounds, because a symbol is a graphic object (WCAG 1.4.11).
struct NoteFolderTintTests {
    private static let names = [NoteFolderTint.brainDumpName, NoteFolderTint.morningName, NoteFolderTint.eveningName]
    private static let appearances: [UIUserInterfaceStyle] = [.light, .dark]

    @Test func assets_resolveInBothAppearances() {
        for name in Self.names {
            for style in Self.appearances {
                #expect(ContrastMath.color(named: name, style: style) != nil, "\(name) is missing for style \(style.rawValue)")
            }
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func symbolColours_haveThreeToOneAgainstTheListBackgrounds(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        // The grouped list: page background and the (elevated) row background.
        let backgrounds = [UIColor.systemGroupedBackground, UIColor.secondarySystemGroupedBackground].map { $0.resolvedColor(with: traits) }
        for name in Self.names {
            let colour = try #require(ContrastMath.color(named: name, style: style))
            for background in backgrounds {
                let ratio = ContrastMath.ratio(colour, background)
                #expect(ratio >= 3, "\(name) has \(ratio):1 in style \(style.rawValue)")
            }
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func expiryText_hasFourPointFiveToOneAgainstTheRowBackground(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let colour = try #require(ContrastMath.color(named: NoteFolderTint.expiryTextName, style: style))
        // The note card sits on the elevated row background of the grouped list.
        let background = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
        let ratio = ContrastMath.ratio(colour, background)
        #expect(ratio >= 4.5, "expiry text has \(ratio):1 in style \(style.rawValue)")
    }

    @Test func roles_mapToTheirColours() {
        #expect(NoteFolderTint.assetName(for: .brainDump) == NoteFolderTint.brainDumpName)
        #expect(NoteFolderTint.assetName(for: .morningRoutine) == NoteFolderTint.morningName)
        #expect(NoteFolderTint.assetName(for: .eveningRoutine) == NoteFolderTint.eveningName)
        #expect(NoteFolderTint.assetName(for: .dreamLog) == NoteFolderTint.eveningName)
        // Every other folder keeps the accent colour.
        for role in [NoteFolderRole.journal, .bibleStudy, .recipes] { #expect(NoteFolderTint.assetName(for: role) == nil) }
        #expect(NoteFolderTint.assetName(for: nil) == nil)
        #expect(NoteFolderTint.color(for: nil) == Color.accentColor)
    }
}
