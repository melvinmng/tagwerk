import Foundation
import TagwerkCore

/// The identifiers of the controls (Control Center, lock screen, Action button). Shared by the app, which reloads the
/// focus control, and the widget extension, which declares them.
enum ControlKind {
    static let water = "tagwerk.control.water"
    static let habit = "tagwerk.control.habit"
    static let dictate = "tagwerk.control.dictate"
    static let focus = "tagwerk.control.focus"
    static let capture = "tagwerk.control.capture"
    static let routine = "tagwerk.control.routine"
    static let shopping = "tagwerk.control.shopping"
}

/// A habit as the configuration dialog of the habit control lists it: name and symbol only, never a streak, a rate or a
/// check mark (privacy decision of #167: the names sit in the App Group container, nothing else about the habits).
struct ControlHabit: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
}

/// The few values the controls need while the app is not running. They live in the `UserDefaults` of the App Group,
/// because a control is rendered by the widget extension, which has no access to the app's database.
/// Holds no notes, no task titles and no health values.
struct ControlState {
    static let focusIsRunningKey = "focus.isRunning"
    static let focusEndsAtKey = "focus.endsAt"
    static let habitsKey = "controls.habits"

    private let defaults: UserDefaults

    /// Tests pass a suite of their own; the app and the extension use `live()`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The App Group's defaults; `nil` when the group is missing (e.g. an unsigned build). The identifier comes from the
    /// Info.plist of the running bundle, never from code.
    static func live(bundle: Bundle = .main) -> ControlState? {
        guard let identifier = bundle.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String,
              identifier.hasPrefix("group."), !identifier.contains("$("),
              let defaults = UserDefaults(suiteName: identifier) else { return nil }
        return ControlState(defaults: defaults)
    }

    // MARK: Focus timer

    /// Remembers whether a session runs. `endsAt` is the projected end of the whole session (`nil` while it is paused),
    /// so the control can tell by the clock that the timer ran out while the app was asleep. Returns whether the stored
    /// values changed, so the caller reloads the control only then.
    @discardableResult
    func writeFocus(isRunning: Bool, endsAt: Date?) -> Bool {
        let end = isRunning ? endsAt : nil
        let changed = defaults.object(forKey: Self.focusIsRunningKey) as? Bool != isRunning
            || defaults.object(forKey: Self.focusEndsAtKey) as? Date != end
        guard changed else { return false }
        defaults.set(isRunning, forKey: Self.focusIsRunningKey)
        if let end { defaults.set(end, forKey: Self.focusEndsAtKey) } else { defaults.removeObject(forKey: Self.focusEndsAtKey) }
        return true
    }

    /// Whether the focus toggle shows "on" at `date`: a session runs and its end has not passed yet.
    func isFocusOn(at date: Date) -> Bool {
        guard defaults.bool(forKey: Self.focusIsRunningKey) else { return false }
        guard let end = defaults.object(forKey: Self.focusEndsAtKey) as? Date else { return true }
        return end > date
    }

    // MARK: Habits

    func writeHabits(_ habits: [ControlHabit]) {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        guard defaults.data(forKey: Self.habitsKey) != data else { return }
        defaults.set(data, forKey: Self.habitsKey)
    }

    func habits() -> [ControlHabit] {
        guard let data = defaults.data(forKey: Self.habitsKey) else { return [] }
        return (try? JSONDecoder().decode([ControlHabit].self, from: data)) ?? []
    }
}
