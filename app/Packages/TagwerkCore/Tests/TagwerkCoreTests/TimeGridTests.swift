import Foundation
import Testing
@testable import TagwerkCore

struct TimeGridTests {
    let nineToSix = WorkHours(startMinutes: 540, endMinutes: 1080)

    @Test func snapped_roundsToQuarterHour() {
        #expect(snapped(minutes: 7) == 0)
        #expect(snapped(minutes: 8) == 15)
        #expect(snapped(minutes: 52) == 45)
        #expect(snapped(minutes: 53) == 60)
    }

    @Test func clampedBlock_beforeMidnightStaysOnDay() {
        #expect(clampedBlock(startMinutes: 1410, duration: 60, dayLength: 1440) == 1380..<1440)
    }

    @Test func clampedBlock_negativeStartClampsToZero() {
        #expect(clampedBlock(startMinutes: -30, duration: 60, dayLength: 1440) == 0..<60)
    }

    @Test func clampedBlock_minimumQuarterHour() {
        #expect(clampedBlock(startMinutes: 600, duration: 5, dayLength: 1440) == 600..<615)
    }

    @Test func freeGaps_betweenEventsWithBuffer() {
        let gaps = freeGaps(hours: nineToSix, busy: [600..<660], lunch: 720..<780, buffer: 10, from: nil)
        #expect(gaps == [540..<590, 670..<720, 780..<1080])
    }

    @Test func freeGaps_today_startsAtNow() {
        let gaps = freeGaps(hours: nineToSix, busy: [600..<660], lunch: 720..<780, buffer: 10, from: 700)
        #expect(gaps == [700..<720, 780..<1080])
    }

    @Test func freeGaps_dropsGapsShorterThanMinimum() {
        let gaps = freeGaps(hours: nineToSix, busy: [550..<1080], lunch: nil, buffer: 0, from: nil)
        #expect(gaps.isEmpty)
    }

    @Test func columns_overlapsSideBySide() {
        #expect(columns(for: [540..<600, 570..<630, 600..<660, 700..<760]) == [0, 1, 0, 0])
    }

    // MARK: Overlap groups (BF1c)

    @Test func overlapGroups_joinsTransitiveOverlaps() {
        // 0 and 1 overlap, 1 and 2 overlap, 0 and 2 do not: still one group of three.
        let groups = overlapGroups(for: [600..<660, 650..<700, 690..<720, 800..<830])
        #expect(groups == [[0, 1, 2], [3]])
    }

    @Test func overlapGroups_listsEachGroupInStartOrder() {
        // Handed in out of order: the later start comes second, groups run from early to late.
        let groups = overlapGroups(for: [800..<830, 630..<700, 600..<660])
        #expect(groups == [[2, 1], [0]])
    }

    @Test func overlapGroups_keepsSingleEntries() {
        #expect(overlapGroups(for: [600..<660, 700..<760]) == [[0], [1]])
        // Touching is no overlap: one entry ends when the next one starts.
        #expect(overlapGroups(for: [600..<660, 660..<720]) == [[0], [1]])
        #expect(overlapGroups(for: []).isEmpty)
    }

    @Test func overlapGroups_agreeWithTheColumns() {
        // Entries of different groups never share a column count above one; a group of one is always column 0.
        let intervals = [540..<600, 570..<630, 600..<660, 700..<760]
        let columnOf = columns(for: intervals)
        for group in overlapGroups(for: intervals) where group.count == 1 {
            #expect(columnOf[group[0]] == 0)
        }
    }

    @Test func collapses_onlyBelowTheMinimum() {
        // Three columns in 120 pt are 40 pt wide: below 44.
        #expect(GridCollapse.collapses(columnCount: 3, availableWidth: 120, minimumColumnWidth: 44))
        // Exactly the minimum still holds.
        #expect(!GridCollapse.collapses(columnCount: 3, availableWidth: 132, minimumColumnWidth: 44))
        #expect(!GridCollapse.collapses(columnCount: 2, availableWidth: 120, minimumColumnWidth: 44))
    }

    @Test func collapses_neverForOneColumn() {
        #expect(!GridCollapse.collapses(columnCount: 1, availableWidth: 10, minimumColumnWidth: 44))
        #expect(!GridCollapse.collapses(columnCount: 0, availableWidth: 10, minimumColumnWidth: 44))
    }
}

