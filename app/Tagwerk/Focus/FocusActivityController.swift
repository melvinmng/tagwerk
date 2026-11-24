import ActivityKit
import Foundation

/// ActivityKit behind `FocusActivityControlling`. Errors are ignored on purpose: without Live Activities (switched off in
/// the settings) the timer still works; nothing about the session is logged.
@MainActor
final class FocusActivityController: FocusActivityControlling {
    private typealias FocusContent = ActivityContent<FocusActivityAttributes.ContentState>

    /// Identifier of the activity of the running session.
    private var activityID: String?

    static func state(for content: FocusActivityContent) -> FocusActivityAttributes.ContentState {
        let kind: FocusActivityAttributes.ContentState.Kind = switch content.kind {
        case .work: .work
        case .shortBreak: .shortBreak
        case .longBreak: .longBreak
        case .finished: .finished
        }
        let nextKind: FocusActivityAttributes.ContentState.Kind? = switch content.nextKind {
        case .work: .work
        case .shortBreak: .shortBreak
        case .longBreak: .longBreak
        case .finished: .finished
        case nil: nil
        }
        return .init(kind: kind, phaseEnd: content.phaseEnd, pausedRemaining: content.pausedRemaining,
                     round: content.round, rounds: content.rounds, phaseSeconds: content.phaseSeconds,
                     nextKind: nextKind, nextPhaseMinutes: content.nextPhaseMinutes)
    }

    /// The activity turns stale when the phase ends, so the lock screen can offer the choices.
    private func activityContent(_ content: FocusActivityContent) -> FocusContent {
        ActivityContent(state: Self.state(for: content), staleDate: content.phaseEnd)
    }

    func adopt() -> Bool {
        let existing = Activity<FocusActivityAttributes>.activities
        guard let first = existing.first else { return false }
        activityID = first.id
        let extras = existing.dropFirst().map(\.id)
        if !extras.isEmpty { Task { await Self.end(only: Set(extras)) } }
        return true
    }

    func start(_ content: FocusActivityContent) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Never two: a leftover activity ends before the new one starts.
        await Self.end(only: nil)
        let attributes = FocusActivityAttributes(title: content.title, isPomodoro: content.isPomodoro, hasTask: content.hasTask)
        activityID = (try? Activity.request(attributes: attributes, content: activityContent(content), pushType: nil))?.id
    }

    func update(_ content: FocusActivityContent) async {
        guard let activityID else { return }
        await Self.update(id: activityID, content: activityContent(content))
    }

    func end() async {
        await Self.end(only: nil)
        activityID = nil
    }

    // Activities are not Sendable, so they are looked up by identifier inside nonisolated helpers.

    private nonisolated static func update(id: String, content: FocusContent) async {
        for activity in Activity<FocusActivityAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    /// Ends the activities with these identifiers, or all of them.
    private nonisolated static func end(only ids: Set<String>?) async {
        for activity in Activity<FocusActivityAttributes>.activities where ids?.contains(activity.id) ?? true {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
