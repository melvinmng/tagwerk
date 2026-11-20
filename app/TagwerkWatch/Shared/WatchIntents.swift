import AppIntents
import Foundation
import TagwerkCore
import WidgetKit

/// The check button of the rectangular complication. It runs in the widget extension, which has no connection to the
/// phone: it records the action in the inbox folder of the shared container, and the watch app sends it from there
/// (at its next start or background refresh). The complication shows the task as done at once (`WatchSnapshot.applying`).
struct WatchCompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufgabe erledigen"
    static let isDiscoverable = false

    @Parameter(title: "Aufgabe")
    var taskKey: String

    @Parameter(title: "Version")
    var version: String

    init() {}

    init(taskKey: String, version: String) {
        self.taskKey = taskKey
        self.version = version
    }

    func perform() async throws -> some IntentResult {
        let action = WatchAction(createdAt: .now, kind: .completeTask(key: taskKey, version: version))
        try? WatchActionInbox.add(action, to: WatchStorage.groupDirectory)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
