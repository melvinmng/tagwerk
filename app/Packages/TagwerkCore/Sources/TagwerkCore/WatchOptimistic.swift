import Foundation

extension WatchSnapshot {
    /// The snapshot with the actions that are not applied by the phone yet already carried out locally: checked tasks
    /// are gone, habits are checked, water is added. Actions the phone reports as applied are skipped (the snapshot
    /// contains them already), and so are actions that were taken back by an `undo` in the same list.
    public func applying(_ actions: [WatchAction]) -> WatchSnapshot {
        let applied = Set(appliedActionIDs)
        let undone = Set(actions.compactMap { action -> UUID? in
            if case .undo(let target) = action.kind { return target }
            return nil
        })
        var result = self
        for action in actions where !applied.contains(action.id) && !undone.contains(action.id) {
            switch action.kind {
            case .completeTask(let key, _):
                result.tasks.removeAll { $0.key == key }
            case .checkHabit(let id, let checked):
                if let index = result.habits.firstIndex(where: { $0.id == id && $0.isCheckable }) {
                    result.habits[index].done = checked
                }
            case .logWater(let milliliters, _):
                result.water?.milliliters += milliliters
            case .undo:
                break
            }
        }
        return result
    }

    /// The habit counter after local changes, for the progress complication: `self` is the snapshot with the actions
    /// applied, `original` the one the phone sent. The counter follows the habits that were checked or unchecked here.
    /// Without a counter (no habits today) there is nothing to adjust.
    public func habitCounter(relativeTo original: WatchSnapshot) -> HabitCounter? {
        guard let counter = original.habitCounter else { return nil }
        let before = Dictionary(uniqueKeysWithValues: original.habits.map { ($0.id, $0.done) })
        var delta = 0
        for habit in habits where before[habit.id] != nil && before[habit.id] != habit.done {
            delta += habit.done ? 1 : -1
        }
        return HabitCounter(done: min(max(counter.done + delta, 0), counter.total), total: counter.total)
    }
}

/// Actions that the complication's buttons record. The widget extension and the watch app both write files in the same
/// folder, so every action is a file of its own: no two writers ever touch the same file. The watch app moves them
/// into its queue when it runs.
public enum WatchActionInbox {
    public static let folderName = "watch-action-inbox"

    private static func folder(in directory: URL) -> URL {
        directory.appending(path: folderName, directoryHint: .isDirectory)
    }

    public static func add(_ action: WatchAction, to directory: URL?) throws {
        guard let directory else { return }
        let folder = folder(in: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(action).write(to: folder.appending(path: "\(action.id.uuidString).json"),
                                         options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The recorded actions in the order they were created, without removing them.
    public static func pending(in directory: URL?) -> [WatchAction] {
        guard let directory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(in: directory), includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(WatchAction.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// Returns the recorded actions and removes their files.
    public static func drain(from directory: URL?) -> [WatchAction] {
        guard let directory else { return [] }
        let actions = pending(in: directory)
        for action in actions {
            try? FileManager.default.removeItem(at: folder(in: directory).appending(path: "\(action.id.uuidString).json"))
        }
        return actions
    }
}
