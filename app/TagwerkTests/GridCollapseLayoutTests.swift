import SwiftUI
import Testing
import TagwerkCore
@testable import Tagwerk

/// Overlapping entries in the hour grid (BF1c): with large text the columns would be too narrow, so the entries become one block; in
/// the standard size they stay side by side. Replaces `PlanOverlapUITests.testOverlappingEntriesStaySideBySideAtStandardSize`; the
/// collapse at the largest text size is asked here as well, and the real grid keeps one UI case in the nightly run
/// (`PlanOverlapUITests.testOverlappingEntriesCollapseAtLargeText`).
///
/// The decision is `GridCollapse.collapses`; its inputs come from `TimelineGridMetrics`, the base values of the scaled metrics of
/// `TimelineCanvas`. The scaling here is `UIFontMetrics` with the text style of the scaled metric (`.caption2` for the label column,
/// `.caption` for the column minimum), which is what `@ScaledMetric(relativeTo:)` does, and the grid is as wide as the window.
struct GridCollapseLayoutTests {
    /// The three appointments of `-TagwerkDemoOverlap` (13:30–14:30, same time).
    private let demoOverlap = [810..<870, 810..<870, 810..<870]

    private func collapses(columnCount: Int, windowWidth: CGFloat, size: UIContentSizeCategory) -> Bool {
        let traits = UITraitCollection(preferredContentSizeCategory: size)
        let label = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: TimelineGridMetrics.hourLabelWidth, compatibleWith: traits)
        let minimum = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: TimelineGridMetrics.minimumColumnWidth, compatibleWith: traits)
        let entriesWidth = TimelineGridMetrics.entriesWidth(gridWidth: windowWidth, scaledLabelWidth: label)
        return GridCollapse.collapses(columnCount: columnCount, availableWidth: Double(entriesWidth), minimumColumnWidth: Double(minimum))
    }

    @Test func demoOverlap_needsThreeColumns() {
        #expect((columns(for: demoOverlap).max() ?? 0) + 1 == 3)
        #expect(overlapGroups(for: demoOverlap) == [[0, 1, 2]])
    }

    @Test(arguments: [390, 402, 440] as [CGFloat])
    func threeOverlappingEntries_stayBesideEachOtherAtTheStandardSize(windowWidth: CGFloat) {
        #expect(!collapses(columnCount: 3, windowWidth: windowWidth, size: .large))
    }

    @Test(arguments: [390, 402, 440] as [CGFloat])
    func threeOverlappingEntries_becomeOneBlockAtTheLargestTextSize(windowWidth: CGFloat) {
        #expect(collapses(columnCount: 3, windowWidth: windowWidth, size: .accessibilityExtraExtraExtraLarge))
    }

    @Test(arguments: [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func aSingleEntryNeverCollapses(size: UIContentSizeCategory) {
        #expect(!collapses(columnCount: 1, windowWidth: 390, size: size))
    }

    @Test func labelColumn_isCappedSoTheEntriesKeepTheirRoom() {
        // At the largest text size the label column grows to its cap and no further.
        let uncapped = TimelineGridMetrics.entriesWidth(gridWidth: 402, scaledLabelWidth: 500)
        #expect(uncapped == 402 - TimelineGridMetrics.hourLabelWidthLimit - TimelineGridMetrics.labelGap)
    }
}
