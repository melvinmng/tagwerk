import Foundation
import TagwerkCore

/// Plans for the neighbouring pages of the day and week view, shown beside the page while it is dragged.
extension PlanningModel {
    /// The days whose plans the previews need: the day before and after (day scope), the seven days of the
    /// week before and after (week scope), nothing in the month.
    static func neighbourRanges(scope: PlanScope, anchor: PlanDay, weekStart: PlanDay,
                                calendar: Calendar) -> [ClosedRange<PlanDay>] {
        switch scope {
        case .day:
            let before = anchor.adding(days: -1, calendar: calendar), after = anchor.adding(days: 1, calendar: calendar)
            return [before...before, after...after]
        case .week:
            let before = weekStart.adding(days: -7, calendar: calendar), after = weekStart.adding(days: 7, calendar: calendar)
            return [before...before.adding(days: 6, calendar: calendar), after...after.adding(days: 6, calendar: calendar)]
        case .month:
            return []
        }
    }

    /// Loads `neighbourPlans` for the shown scope and anchor. The plans carry no AI suggestions. The result is
    /// dropped when the scope or the anchor changed in the meantime.
    func loadNeighbours() async {
        let scope = self.scope, anchor = self.anchor
        let ranges = Self.neighbourRanges(scope: scope, anchor: anchor, weekStart: range.lowerBound, calendar: calendar)
        var result: [PlanDay: DayPlan] = [:]
        for range in ranges {
            for plan in await dayPlans(in: range) { result[plan.day] = plan }
        }
        guard !Task.isCancelled, self.scope == scope, self.anchor == anchor else { return }
        neighbourPlans = result
    }

    /// Starts `loadNeighbours()` after a reload; an earlier run that is still going is cancelled. It never delays `days`.
    func scheduleNeighbourLoad() {
        guard loadsNeighboursAfterReload else { return }
        neighbourLoad?.cancel()
        neighbourLoad = Task { [weak self] in await self?.loadNeighbours() }
    }
}
