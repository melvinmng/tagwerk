import Foundation
import TagwerkCore

/// Where the watch app and the complications keep their files. Both run on the watch and share the App Group
/// container of the watch (the group identifier is the phone's, the containers are separate). The identifier comes from
/// Info.plist, never from code.
enum WatchStorage {
    /// `<container>/Library/Application Support`; `nil` when the group is missing (e.g. an unsigned build).
    static var groupDirectory: URL? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String,
              identifier.hasPrefix("group."), !identifier.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return container.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// The watch app falls back to its own folder, so it keeps working (without complications) when the group is missing.
    static var appDirectory: URL {
        groupDirectory ?? URL.applicationSupportDirectory.appending(path: "Watch", directoryHint: .isDirectory)
    }
}

extension Calendar {
    /// Gregorian calendar with Monday first in the watch's time zone, like the phone's planning calendar.
    static var watch: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }
}
