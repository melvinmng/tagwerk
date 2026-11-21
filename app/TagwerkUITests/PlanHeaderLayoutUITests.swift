import XCTest

/// The date title of the plan header next to the bar buttons (PL16b): it takes the longest form that fits and never
/// touches the buttons. Runs the header in German and English at three text sizes and prints the measurements that set
/// `PlanHeaderMetrics.trailingReserve` (lines starting with "HEADER").
final class PlanHeaderLayoutUITests: UITestCase {
    private var arguments: [String] = []
    override var extraLaunchArguments: [String] { arguments }

    private struct Variant {
        let name: String
        let language: [String]
        let textSize: [String]
    }

    private static let variants = [
        Variant(name: "de standard", language: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"], textSize: []),
        Variant(name: "de XXXL", language: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"], textSize: ["-TagwerkUITestTextSize", "xxxLarge"]),
        Variant(name: "de AX1", language: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"], textSize: ["-TagwerkUITestTextSize", "accessibility1"]),
        Variant(name: "en standard", language: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], textSize: []),
        Variant(name: "en XXXL", language: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], textSize: ["-TagwerkUITestTextSize", "xxxLarge"]),
        Variant(name: "en AX1", language: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], textSize: ["-TagwerkUITestTextSize", "accessibility1"]),
        Variant(name: "de AX5", language: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"], textSize: ["-TagwerkUITestTextSize", "accessibility5"]),
        Variant(name: "en AX5", language: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], textSize: ["-TagwerkUITestTextSize", "accessibility5"]),
    ]

    /// Smallest distance the title may come to the first bar button.
    private static let minimumGap: CGFloat = 8

    func testTitleNeverTouchesTheBarButtons() {
        for variant in Self.variants {
            arguments = variant.language + variant.textSize
            app.terminate()
            launchApp()
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout))
            // Five days on from Saturday cover the longest weekdays: Wednesday and Thursday.
            for day in 0...5 {
                if day > 0 { tapButton(variant.language.contains("(en)") ? "Next day" : "Nächster Tag") }
                check(variant, in: bar, day: day)
            }
        }
    }

    private func check(_ variant: Variant, in bar: XCUIElement, day: Int) {
        // The title is the one text of the bar that carries the period caption as its value.
        let title = bar.staticTexts.matching(NSPredicate(format: "value != nil AND value != ''")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "\(variant.name): no date title in the bar")
        // Let the page change finish before measuring.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let titleFrame = title.frame
        let trailing = bar.buttons.allElementsBoundByIndex.map(\.frame).filter { !titleFrame.contains($0) && $0.minX > titleFrame.minX }
        let firstTrailing = trailing.map(\.minX).min() ?? .infinity
        let width = app.windows.firstMatch.frame.width
        let gap = firstTrailing - titleFrame.maxX
        // Measurements for `PlanHeaderMetrics`: the title element includes the chevron; `trailingWidth` is the space the
        // buttons take at the trailing edge.
        print("HEADER \(variant.name) day+\(day): window=\(width) title=\(title.label) titleWidth=\(titleFrame.width) "
            + "titleMinX=\(titleFrame.minX) firstTrailingX=\(firstTrailing) gap=\(gap) trailingWidth=\(width - firstTrailing)")
        XCTAssertGreaterThanOrEqual(gap, Self.minimumGap, "\(variant.name) day+\(day): the title \(title.label) comes too close to the bar buttons")
    }
}
