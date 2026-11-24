import CoreGraphics
import Testing
@testable import Tagwerk

struct PageDragTests {
    @Test func offset_verticalDrag_isNil() {
        #expect(PageDrag.offset(translation: CGSize(width: 4, height: 120), canGoBack: true, canGoForward: true) == nil)
    }

    @Test func offset_diagonalBelowRatio_isNil() {
        // 100 sideways but 60 vertical: not twice as far sideways as up or down.
        #expect(PageDrag.offset(translation: CGSize(width: 100, height: 60), canGoBack: true, canGoForward: true) == nil)
        // Not yet past the activation distance.
        #expect(PageDrag.offset(translation: CGSize(width: 8, height: 0), canGoBack: true, canGoForward: true) == nil)
    }

    @Test func offset_horizontal_followsFinger() {
        #expect(PageDrag.offset(translation: CGSize(width: 90, height: 10), canGoBack: true, canGoForward: true) == 90)
        #expect(PageDrag.offset(translation: CGSize(width: -140, height: 20), canGoBack: true, canGoForward: true) == -140)
    }

    @Test func offset_blockedEdge_isDamped() {
        // No later day: dragging left (forward) is a rubber band, capped.
        let damped = PageDrag.offset(translation: CGSize(width: -100, height: 0), canGoBack: true, canGoForward: false)
        #expect(damped == -25)
        let capped = PageDrag.offset(translation: CGSize(width: -300, height: 0), canGoBack: true, canGoForward: false)
        #expect(capped == -PageDrag.rubberBandLimit)
        // The other direction is free.
        #expect(PageDrag.offset(translation: CGSize(width: 100, height: 0), canGoBack: true, canGoForward: false) == 100)
    }

    @Test func outcome_pastThreshold_pages() {
        let width: CGFloat = 390
        #expect(PageDrag.outcome(translation: CGSize(width: 90, height: 5), predicted: CGSize(width: 90, height: 5), width: width,
                                 canGoBack: true, canGoForward: true) == .back)
        #expect(PageDrag.outcome(translation: CGSize(width: -90, height: 5), predicted: CGSize(width: -90, height: 5), width: width,
                                 canGoBack: true, canGoForward: true) == .forward)
    }

    @Test func outcome_flickWithPrediction_pages() {
        // Only 40 pt, but the finger was moving fast: it would have ended far beyond half the width.
        #expect(PageDrag.outcome(translation: CGSize(width: -40, height: 2), predicted: CGSize(width: -260, height: 5), width: 390,
                                 canGoBack: true, canGoForward: true) == .forward)
        // A flick that hardly moved is not a page.
        #expect(PageDrag.outcome(translation: CGSize(width: -10, height: 0), predicted: CGSize(width: -400, height: 0), width: 390,
                                 canGoBack: true, canGoForward: true) == nil)
    }

    @Test func outcome_shortDrag_settles() {
        #expect(PageDrag.outcome(translation: CGSize(width: 50, height: 0), predicted: CGSize(width: 60, height: 0), width: 390,
                                 canGoBack: true, canGoForward: true) == nil)
        // A flick against the drag direction does not count.
        #expect(PageDrag.outcome(translation: CGSize(width: 50, height: 0), predicted: CGSize(width: -300, height: 0), width: 390,
                                 canGoBack: true, canGoForward: true) == nil)
    }

    @Test func outcome_blockedEdge_settles() {
        #expect(PageDrag.outcome(translation: CGSize(width: -200, height: 0), predicted: CGSize(width: -300, height: 0), width: 390,
                                 canGoBack: true, canGoForward: false) == nil)
        #expect(PageDrag.outcome(translation: CGSize(width: 200, height: 0), predicted: CGSize(width: 300, height: 0), width: 390,
                                 canGoBack: false, canGoForward: true) == nil)
    }

    @Test func outcome_matchesPageSwipeDirection() {
        // The same translations give the same direction as the release-only `PageSwipe` rule.
        let cases: [CGSize] = [CGSize(width: 90, height: 10), CGSize(width: -90, height: -12), CGSize(width: 100, height: 60),
                               CGSize(width: 70, height: 0)]
        for translation in cases where abs(translation.width) >= PageSwipe.minimumDistance {
            let expected = PageSwipe.direction(start: CGPoint(x: 100, y: 300), translation: translation)
            let actual = PageDrag.outcome(translation: translation, predicted: translation, width: 390, canGoBack: true, canGoForward: true)
            #expect(actual == expected)
        }
    }

    // MARK: Prevailing page (PL6b)

    @Test func prevailingPage_belowHalf_isNil() {
        #expect(PageDrag.prevailingPage(offset: 150, width: 390, canGoBack: true, canGoForward: true) == nil)
        #expect(PageDrag.prevailingPage(offset: -195, width: 390, canGoBack: true, canGoForward: true) == nil)
        #expect(PageDrag.prevailingPage(offset: 0, width: 390, canGoBack: true, canGoForward: true) == nil)
    }

    @Test func prevailingPage_aboveHalf_isTheNeighbour() {
        // Dragging right shows the previous page, dragging left the next one.
        #expect(PageDrag.prevailingPage(offset: 200, width: 390, canGoBack: true, canGoForward: true) == .back)
        #expect(PageDrag.prevailingPage(offset: -260, width: 390, canGoBack: true, canGoForward: true) == .forward)
    }

    @Test func prevailingPage_atBlockedEdge_isNil() {
        #expect(PageDrag.prevailingPage(offset: 300, width: 390, canGoBack: false, canGoForward: true) == nil)
        #expect(PageDrag.prevailingPage(offset: -300, width: 390, canGoBack: true, canGoForward: false) == nil)
    }

    @Test func prevailingPage_withoutWidth_isNil() {
        #expect(PageDrag.prevailingPage(offset: 10, width: 0, canGoBack: true, canGoForward: true) == nil)
    }
}

