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

    /// Loads `neighbourPlans` for the shown scope and anchor. Day scope: the plans carry the stored AI suggestions and
    /// come with the state of the page (`neighbourExtras`), so a preview and the page after it show the same cards.
    /// Week scope: no suggestions. The result is dropped when the scope or the anchor changed in the meantime.
    func loadNeighbours() async {
        let scope = self.scope, anchor = self.anchor
        let ranges = Self.neighbourRanges(scope: scope, anchor: anchor, weekStart: range.lowerBound, calendar: calendar)
        var plans: [PlanDay: DayPlan] = [:]
        var extras: [PlanDay: DayPageExtras] = [:]
        for range in ranges {
            if scope == .day {
                if let page = await dayPage(range.lowerBound) {
                    plans[range.lowerBound] = page.plan
                    extras[range.lowerBound] = page.extras
                }
                // The next day's work starts in a later turn, so a gesture in between is not held up.
                await Task.yield()
            } else {
                for plan in await dayPlans(in: range) { plans[plan.day] = plan }
            }
        }
        guard !Task.isCancelled, self.scope == scope, self.anchor == anchor else { return }
        neighbourPlans = plans
        neighbourExtras = extras
    }

    /// Starts the loads that follow a reload: the neighbour plans and missing travel times (an earlier run
    /// of either that is still going is cancelled). Neither delays `days`.
    func scheduleBackgroundLoads() {
        guard runsBackgroundLoads else { return }
        neighbourLoad?.cancel()
        neighbourLoad = Task { [weak self] in await self?.loadNeighbours() }
        travelTimeRefresh?.cancel()
        travelTimeRefresh = Task { [weak self] in _ = await self?.refreshTravelTimes() }
    }
}
