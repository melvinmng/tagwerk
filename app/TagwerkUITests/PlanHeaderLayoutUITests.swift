import XCTest

/// The date title of the plan header next to the bar buttons (PL16b): it takes the longest form that fits and never
/// touches the buttons. Runs the header in German and English at Standard, XXXL and AX1 and prints the measurements that
/// set `PlanHeaderMetrics.trailingReserve` (lines starting with "HEADER"). The AX5 size is left out to keep the run short.
///
/// The run is kept short on purpose (every variant needs its own app launch): the first variant uses the launch of `setUp`,
/// and every day is measured with one snapshot of the bar instead of one query per button.
final class PlanHeaderLayoutUITests: UITestCase {
    private var arguments: [String] = []
    override var extraLaunchArguments: [String] { arguments }

    private struct Variant {
        let name: String
        let language: [String]
        let textSize: [String]
    }

    private static let german = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
    private static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    private static let variants = [
        Variant(name: "de standard", language: german, textSize: []),
        Variant(name: "de XXXL", language: german, textSize: ["-TagwerkUITestTextSize", "xxxLarge"]),
        Variant(name: "de AX1", language: german, textSize: ["-TagwerkUITestTextSize", "accessibility1"]),
        Variant(name: "en standard", language: english, textSize: []),
        Variant(name: "en XXXL", language: english, textSize: ["-TagwerkUITestTextSize", "xxxLarge"]),
        Variant(name: "en AX1", language: english, textSize: ["-TagwerkUITestTextSize", "accessibility1"]),
    ]

    /// Smallest distance the title may come to the first bar button.
    private static let minimumGap: CGFloat = 8

    /// Days measured, counted from the first day of the run. Five days on from a Saturday cover the longest weekdays,
    /// Wednesday and Thursday; the Sunday (day 1) is stepped over without a measurement.
    private static let measuredDays: Set<Int> = [0, 2, 3, 4, 5]

    func testTitleNeverTouchesTheBarButtons() {
        for (index, variant) in Self.variants.enumerated() {
            // The first variant is what `setUp` has launched already (German, standard text size).
            if index > 0 {
                arguments = variant.language + variant.textSize
                app.terminate()
                launchApp()
            }
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(bar.exists || bar.waitForExistence(timeout: Self.timeout), "\(variant.name): no navigation bar")
            // `waitForExistence` first looks after a second, so the button is only waited for when it is not there yet.
            let nextDay = app.buttons[variant.language == Self.english ? "Next day" : "Nächster Tag"].firstMatch
            for day in 0...5 {
                if day > 0 {
                    XCTAssertTrue(nextDay.exists || nextDay.waitForExistence(timeout: Self.timeout), "\(variant.name): no next day button")
                    nextDay.tap()
                }
                if Self.measuredDays.contains(day) { check(variant, in: bar, day: day) }
            }
        }
    }

    private func check(_ variant: Variant, in bar: XCUIElement, day: Int) {
        // Let the page change finish before measuring.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        // One snapshot of the whole bar: a query per button would take one round trip each.
        var elements = flattened(bar)
        if title(in: elements) == nil {
            XCTAssertTrue(bar.staticTexts.matching(NSPredicate(format: "value != nil AND value != ''")).firstMatch
                .waitForExistence(timeout: Self.timeout), "\(variant.name) day+\(day): no date title in the bar")
            elements = flattened(bar)
        }
        guard let title = title(in: elements) else {
            XCTFail("\(variant.name) day+\(day): no date title in the bar")
            return
        }
        let titleFrame = title.frame
        let trailing = elements.filter { $0.elementType == .button && !titleFrame.contains($0.frame) && $0.frame.minX > titleFrame.minX }
        let firstTrailing = trailing.map(\.frame.minX).min() ?? .infinity
        let width = app.windows.firstMatch.frame.width
        let gap = firstTrailing - titleFrame.maxX
        // Measurements for `PlanHeaderMetrics`: the title element includes the chevron; `trailingWidth` is the space the
        // buttons take at the trailing edge.
        print("HEADER \(variant.name) day+\(day): window=\(width) title=\(title.label) titleWidth=\(titleFrame.width) "
            + "titleMinX=\(titleFrame.minX) firstTrailingX=\(firstTrailing) gap=\(gap) trailingWidth=\(width - firstTrailing)")
        XCTAssertGreaterThanOrEqual(gap, Self.minimumGap, "\(variant.name) day+\(day): the title \(title.label) comes too close to the bar buttons")
    }

    /// All elements below the bar, taken from one snapshot.
    private func flattened(_ bar: XCUIElement) -> [XCUIElementSnapshot] {
        guard let snapshot = try? bar.snapshot() else { return [] }
        var result: [XCUIElementSnapshot] = []
        func collect(_ element: XCUIElementSnapshot) {
            result.append(element)
            element.children.forEach(collect)
        }
        collect(snapshot)
        return result
    }

    /// The title is the one text of the bar that carries the period caption as its value.
    private func title(in elements: [XCUIElementSnapshot]) -> XCUIElementSnapshot? {
        elements.first { element in
            guard element.elementType == .staticText, let value = element.value as? String else { return false }
            return !value.isEmpty
        }
    }
}
