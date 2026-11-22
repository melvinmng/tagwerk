import Foundation

/// What "Unerledigtes verschieben" tells before anything moves (RO9c) and when its row is offered (RO10a). Pure rules;
/// the free minutes come from the capacity of the target day (`capacity(_:)`), nothing is counted again here.
public enum LeftoverPreview {
    /// Whether the open tasks fit into the target day.
    public enum Fit: Sendable, Equatable {
        /// The estimates fit; `freeMinutes` is what the day has free.
        case fits(freeMinutes: Int)
        /// The estimates need more than the day has free.
        case tight(freeMinutes: Int, neededMinutes: Int)
        /// The target day is no working day.
        case dayOff
        /// The capacity of the target day is not known (yet), so nothing is promised.
        case unknown
    }

    /// Whether the estimated minutes of the tasks fit into the free minutes of the target day. `freeMinutes` is `nil` while
    /// the capacity of the day is not known; a negative value (an overbooked day) counts as no free time.
    public static func fit(neededMinutes: Int, freeMinutes: Int?, isDayOff: Bool) -> Fit {
        if isDayOff { return .dayOff }
        guard let freeMinutes else { return .unknown }
        let free = max(0, freeMinutes)
        return neededMinutes <= free ? .fits(freeMinutes: free) : .tight(freeMinutes: free, neededMinutes: neededMinutes)
    }

    /// How long before the end of work the row of the capacity card appears without an overbooked day.
    public static let lateAfternoonLeadMinutes = 120

    /// Whether the capacity card offers "Unerledigtes verschieben": there are open tasks of today and either the day is
    /// overbooked or it is late afternoon (from two hours before the end of work on). Before that the card stays at its
    /// two lines.
    public static func showsLeftoverLine(leftoverCount: Int, isOverCapacity: Bool, minutesOfDay: Int, workdayEndMinutes: Int) -> Bool {
        guard leftoverCount > 0 else { return false }
        return isOverCapacity || minutesOfDay >= workdayEndMinutes - lateAfternoonLeadMinutes
    }
}
