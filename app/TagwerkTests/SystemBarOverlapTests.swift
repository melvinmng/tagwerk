import CoreGraphics
import Testing

/// The rule that ignores contrast findings of content under a system bar (`app/TagwerkUITests/SystemBarOverlap.swift`).
struct SystemBarOverlapTests {
    /// iPhone 17 Pro: 402 × 874 pt.
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
    private let navigationBar = SystemBarOverlap.Bar(name: "navigation bar", frame: CGRect(x: 0, y: 0, width: 402, height: 105))
    private let tabBar = SystemBarOverlap.Bar(name: "tab bar", frame: CGRect(x: 0, y: 791, width: 402, height: 83))
    private var bars: [SystemBarOverlap.Bar] { [navigationBar, tabBar] }

    @Test func elementInsideNavigationBar_isCovered() {
        let element = CGRect(x: 20, y: 32, width: 300, height: 69)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == navigationBar)
    }

    @Test func navigationBarInTheAccessibilityTree_reachesUnderTheStatusBar() {
        // Measured on the iPhone 17 Pro: the navigation bar of "Planen" has the frame y 62 to 116 pt, below the status bar. The all-day pill
        // "Projektwoche" (y 32 to 101 pt) lies 56 % in that band, and completely in the band extended to the top of the screen.
        let measuredBar = SystemBarOverlap.Bar(name: "navigation bar", frame: CGRect(x: 0, y: 62, width: 402, height: 54))
        let pill = CGRect(x: 16, y: 32, width: 370, height: 69)
        #expect(abs(SystemBarOverlap.coveredShare(of: pill, by: measuredBar.frame, within: screen) - 39.0 / 69.0) < 0.0001)
        let extended = measuredBar.extendedToTop(of: screen)
        #expect(extended.frame == CGRect(x: 0, y: 0, width: 402, height: 116))
        #expect(SystemBarOverlap.coveredShare(of: pill, by: extended.frame, within: screen) == 1)
        #expect(SystemBarOverlap.bar(covering: pill, in: [extended], within: screen) == extended)
    }

    @Test func extendingToTheTop_leavesABarAtTheTopAlone() {
        #expect(navigationBar.extendedToTop(of: screen) == navigationBar)
    }

    @Test func elementInsideTabBar_isCovered() {
        let element = CGRect(x: 19.8, y: 808.9, width: 71.7, height: 29.7)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == tabBar)
    }

    @Test func elementBeyondLowerScreenEdge_isJudgedByItsVisiblePart() {
        // Frame of the headline block of the finding: y 811 to 913 on a 874 pt screen; the visible part (811 to 874) lies inside the tab bar.
        let element = CGRect(x: 16, y: 811, width: 370, height: 102)
        #expect(SystemBarOverlap.coveredShare(of: element, by: tabBar.frame, within: screen) == 1)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == tabBar)
    }

    @Test func elementBetweenTheBars_isNotCovered() {
        let element = CGRect(x: 20, y: 300, width: 300, height: 60)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == nil)
    }

    @Test func elementTouchingTheBarOnlyAtItsEdge_isNotCovered() {
        let element = CGRect(x: 20, y: 105, width: 300, height: 40)
        #expect(SystemBarOverlap.coveredShare(of: element, by: navigationBar.frame, within: screen) == 0)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == nil)
    }

    @Test func elementCoveredBelowHalf_isNotIgnored() {
        // 40 pt high, 15 pt of it in the navigation bar: 37.5 %.
        let element = CGRect(x: 20, y: 90, width: 300, height: 40)
        #expect(SystemBarOverlap.coveredShare(of: element, by: navigationBar.frame, within: screen) == 0.375)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == nil)
    }

    @Test func elementCoveredExactlyByHalf_isIgnored() {
        let element = CGRect(x: 20, y: 85, width: 300, height: 40)
        #expect(SystemBarOverlap.coveredShare(of: element, by: navigationBar.frame, within: screen) == 0.5)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == navigationBar)
    }

    @Test func elementOutsideTheScreen_isNotCovered() {
        let element = CGRect(x: 20, y: 900, width: 300, height: 40)
        #expect(SystemBarOverlap.coveredShare(of: element, by: tabBar.frame, within: screen) == 0)
        #expect(SystemBarOverlap.bar(covering: element, in: bars, within: screen) == nil)
    }

    @Test func elementWithoutFrame_isNeverCovered() {
        #expect(SystemBarOverlap.bar(covering: .zero, in: bars, within: screen) == nil)
        #expect(SystemBarOverlap.bar(covering: .null, in: bars, within: screen) == nil)
    }

    @Test func noBars_coverNothing() {
        #expect(SystemBarOverlap.bar(covering: CGRect(x: 0, y: 10, width: 100, height: 20), in: [], within: screen) == nil)
    }

    @Test func elementCoveredByTwoBars_takesTheBarWithTheLargerShare() {
        // Two overlapping bands, as a sheet bar over a page bar.
        let smallScreen = CGRect(x: 0, y: 0, width: 402, height: 200)
        let top = SystemBarOverlap.Bar(name: "navigation bar", frame: CGRect(x: 0, y: 0, width: 402, height: 60))
        let bottom = SystemBarOverlap.Bar(name: "tab bar", frame: CGRect(x: 0, y: 45, width: 402, height: 100))
        // Overlapping bands (a sheet bar over a page bar): element y 10 to 60: 100 % in the top bar, 30 % in the bottom bar.
        #expect(SystemBarOverlap.bar(covering: CGRect(x: 0, y: 10, width: 402, height: 50), in: [bottom, top], within: smallScreen) == top)
        // Element y 50 to 70: 50 % in the top bar (50 to 60), 100 % in the bottom bar (50 to 70): both reach one half, the larger share wins.
        #expect(SystemBarOverlap.bar(covering: CGRect(x: 0, y: 50, width: 402, height: 20), in: [top, bottom], within: smallScreen) == bottom)
    }

    @Test func fullHeightElement_isNotCoveredByEitherBar() {
        // 105 pt of 874 pt lie in the navigation bar and 83 pt in the tab bar; neither share reaches one half.
        let tall = CGRect(x: 0, y: 0, width: 402, height: 874)
        #expect(SystemBarOverlap.bar(covering: tall, in: bars, within: screen) == nil)
    }
}
