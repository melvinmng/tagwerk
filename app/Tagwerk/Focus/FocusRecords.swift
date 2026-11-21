import Foundation
import SwiftData
import TagwerkCore

/// One focus timer session. Stored only on this device; `title` is kept for display and never sent anywhere.
/// The timer state is kept as timestamps, so a session survives the app being closed (plan P3, review focus 1).
@Model
final class FocusSessionRecord {
    @Attribute(.unique) var id: UUID = UUID()
    /// `TaskID.key`; `nil` for a free session.
    var taskKey: String? = nil
    /// Identifier of the time block the session was started from.
    var blockEventID: String? = nil
    var title: String = ""
    var start: Date = Date.distantPast
    /// JSON of `[DateInterval]`, the finished pauses.
    var pausesJSON: Data? = nil
    var pausedSince: Date? = nil
    /// JSON of `[Date]`, the moments breaks were skipped.
    var skipsJSON: Data? = nil
    /// JSON of `FocusTimerSettings` as they were at the start.
    var settingsJSON: Data? = nil
    var endedAt: Date? = nil
    /// `FocusOutcome` raw value; `nil` while the session runs.
    var outcomeRaw: String? = nil
    var focusedSeconds: Int = 0
    /// Identifier of the Live Activity that shows this session.
    var activityID: String? = nil

    init(id: UUID = UUID(), taskKey: String?, blockEventID: String?, title: String, state: FocusTimerState) {
        self.id = id
        self.taskKey = taskKey
        self.blockEventID = blockEventID
        self.title = title
        self.start = state.start
        apply(state)
    }

    var isRunning: Bool { outcomeRaw == nil && endedAt == nil }

    var outcome: FocusOutcome? {
        get { outcomeRaw.flatMap(FocusOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var state: FocusTimerState {
        let settings = settingsJSON.flatMap { try? JSONDecoder().decode(FocusTimerSettings.self, from: $0) } ?? FocusTimerSettings()
        let pauses = pausesJSON.flatMap { try? JSONDecoder().decode([DateInterval].self, from: $0) } ?? []
        let skips = skipsJSON.flatMap { try? JSONDecoder().decode([Date].self, from: $0) } ?? []
        return FocusTimerState(start: start, settings: settings, pauses: pauses, pausedSince: pausedSince, skips: skips, endedAt: endedAt)
    }

    func apply(_ state: FocusTimerState) {
        start = state.start
        pausesJSON = state.pauses.isEmpty ? nil : try? JSONEncoder().encode(state.pauses)
        pausedSince = state.pausedSince
        skipsJSON = state.skips.isEmpty ? nil : try? JSONEncoder().encode(state.skips)
        settingsJSON = try? JSONEncoder().encode(state.settings)
        endedAt = state.endedAt
    }

    /// The brick of the collection this session left, if any. A stored `aborted` outcome reads as "ended early".
    var piece: FocusRewardPiece? {
        guard let outcome else { return nil }
        return FocusReward.piece(focusedMinutes: focusedSeconds / 60, outcome: outcome)
    }
}

/// One measured completion of a task (plan P3, #162). Stored only on this device; only `expectedMinutes` derived from
/// many of them ever leaves it, and only to the AI planning.
@Model
final class EffortSampleRecord {
    @Attribute(.unique) var id: UUID = UUID()
    /// `TaskID.key`.
    var taskKey: String = ""
    var sourceRaw: String = TaskSource.local.rawValue
    /// JSON of `[String]`.
    var labelsJSON: Data? = nil
    var estimateMinutes: Int? = nil
    var actualMinutes: Int = 0
    var methodRaw: String = EffortMethod.focus.rawValue
    var completedAt: Date = Date.distantPast
    /// The block that was cut at the completion, its end before, and its end after (to recognize later changes).
    var trimmedEventID: String? = nil
    var trimmedOriginalEnd: Date? = nil
    var trimmedNewEnd: Date? = nil

    init(taskKey: String, source: TaskSource, labels: [String], estimateMinutes: Int?, actualMinutes: Int,
         method: EffortMethod, completedAt: Date) {
        self.taskKey = taskKey
        self.sourceRaw = source.rawValue
        self.labelsJSON = labels.isEmpty ? nil : try? JSONEncoder().encode(labels)
        self.estimateMinutes = estimateMinutes
        self.actualMinutes = actualMinutes
        self.methodRaw = method.rawValue
        self.completedAt = completedAt
    }

    var value: EffortSample {
        EffortSample(source: TaskSource(rawValue: sourceRaw) ?? .local,
                     labels: labelsJSON.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [],
                     estimateMinutes: estimateMinutes, actualMinutes: actualMinutes, completedAt: completedAt)
    }
}
