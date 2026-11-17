import Foundation
import SwiftData

/// User preferences, stored as a single SwiftData object.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class AppSettings {
    var workdayStartMinutes: Int = 540
    var workdayEndMinutes: Int = 1080
    var lunchStartMinutes: Int = 720
    var lunchDurationMinutes: Int = 60
    var bufferMinutes: Int = 10
    var leadTimeMinutes: Int = 120
    /// `nil` means the default selection (see `CalendarSelection.defaultSelected`).
    var selectedCalendarIDs: [String]? = nil
    /// `nil` means all reminder lists.
    var selectedReminderListIDs: [String]? = nil
    var setupCompleted: Bool = false
    /// `nil` means the default project selection (projects with assigned open issues).
    var selectedProjectIDs: [String]? = nil

    init() {}

    /// Returns the single settings object, creating it on first access.
    @MainActor
    static func current(in context: ModelContext) throws -> AppSettings {
        if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}
