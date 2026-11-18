import BackgroundTasks
import Foundation
import os

/// The background app refresh (Phase 2 §8, §12.8): loads tasks (GitHub over the network or from the cache)
/// and reschedules the notifications. It receives only loading and scheduling steps, never an AI feature (§8.4).
@MainActor
final class BackgroundRefresh {
    /// Fixed identifier, independent of the locally configured bundle ID; listed in `project.yml`.
    nonisolated static let identifier = "tagwerk.refresh"
    /// Earliest start of the next run after this one or after moving to the background.
    nonisolated static let interval: TimeInterval = 2 * 60 * 60

    /// Registers sources that need it (GitHub when signed in); `true` when that already loaded all sources.
    private let prepare: () async -> Bool
    private let reload: () async -> Void
    private let reschedule: () async -> Void
    /// Rewrites the widget snapshot after loading (phase 4); keeps the plan part when sources did not load in time.
    private let writeSnapshot: () -> Void
    private let submit: (Date) async throws -> Void
    private let now: () -> Date
    /// iOS grants about 30 s; loading gets part of it, scheduling uses whatever has arrived by then.
    private let loadBudget: Duration
    private let log = Logger(subsystem: "local.tagwerk", category: "background")

    init(prepare: @escaping () async -> Bool, reload: @escaping () async -> Void, reschedule: @escaping () async -> Void,
         writeSnapshot: @escaping () -> Void = {},
         submit: @escaping (Date) async throws -> Void = BackgroundRefresh.submitToSystem, now: @escaping () -> Date = Date.init,
         loadBudget: Duration = .seconds(20)) {
        self.prepare = prepare
        self.reload = reload
        self.reschedule = reschedule
        self.writeSnapshot = writeSnapshot
        self.submit = submit
        self.now = now
        self.loadBudget = loadBudget
    }

    /// One run. The next request is submitted first, so a run that iOS ends early keeps the chain going.
    func run() async {
        await submitNext()
        let prepare = self.prepare
        let reload = self.reload
        await Self.waitAtMost(loadBudget) {
            if await !prepare() { await reload() }
        }
        await reschedule()
        writeSnapshot()
    }

    /// Asks iOS for the next run; failures (e.g. in the simulator) are only logged.
    func submitNext() async {
        do {
            try await submit(now().addingTimeInterval(Self.interval))
        } catch {
            log.notice("Submitting the background refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func submitToSystem(_ earliest: Date) async throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliest
        try await BGTaskScheduler.shared.submitTaskRequest(request)
    }

    /// Runs `work` and returns when it finished or `budget` passed, whichever comes first. The work keeps running.
    private static func waitAtMost(_ budget: Duration, _ work: @escaping @MainActor () async -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = ResumeOnce(continuation)
            Task { @MainActor in
                await work()
                resume.fire()
            }
            Task { @MainActor in
                try? await Task.sleep(for: budget)
                resume.fire()
            }
        }
    }
}

/// Resumes a continuation exactly once; used on the main actor only.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func fire() {
        continuation?.resume()
        continuation = nil
    }
}
