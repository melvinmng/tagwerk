import Foundation
import HealthBridge
import OSLog

/// Mirrors own entries to Health and catches up on failures (phase 3 design §4.2).
///
/// Runs are serialized: a request during a run makes the running chain loop once more instead of starting
/// a second writer, so an entry is never written twice and a deletion never overtakes its save.
/// Logs carry error codes only, never values.
@MainActor
final class HealthMirror {
    /// Health deletions wait this long, so "Widerrufen" can bring an entry back without touching Health.
    static let undoWindow: TimeInterval = 4

    private let store: IntakeStore
    private let health: any HealthStoring
    private let now: () -> Date
    private var running: Task<Void, Never>?
    private var needsAnotherRun = false
    private var delayedRun: Task<Void, Never>?
    private let logger = Logger(subsystem: "local.tagwerk", category: "health")

    init(store: IntakeStore, health: any HealthStoring, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.health = health
        self.now = now
    }

    /// Writes unsynced entries and executes due deletions. Does nothing before the user was asked for access.
    func sync() async {
        if let running {
            needsAnotherRun = true
            await running.value
            return
        }
        let chain = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                needsAnotherRun = false
                await runOnce()
            } while needsAnotherRun
            // Cleared inside the chain, so a request after the last loop check starts a new chain.
            running = nil
        }
        running = chain
        await chain.value
    }

    /// The group "weitere Nährwerte nach Health" was allowed: meals that carry such values are mirrored again, once.
    func furtherNutrientsGranted() async {
        store.markMealsWithFurtherNutrientsUnsynced()
        await sync()
    }

    /// A run after the undo window, for deletions that are waiting.
    func syncAfterUndoWindow() {
        delayedRun?.cancel()
        delayedRun = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow + 0.5))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    private func runOnce() async {
        let access = await health.access()
        // The body weight has its own permission group (`body`), asked at the first saved weight: it is mirrored even though the
        // core group was never asked, and it waits while its own group was not asked.
        let bodyAsked = await health.groupAccess(.body) == .asked
        let coreOpen = access.wasAsked && access != .denied
        for unsynced in store.unsyncedEntries() {
            if case .weight = unsynced.entry {
                guard bodyAsked else { continue }
            } else {
                guard coreOpen else { continue }
            }
            do {
                let complete: Bool = switch unsynced.entry.healthValue(version: unsynced.version) {
                case .meal(let meal): try await health.save(meal)
                case .drink(let drink): try await health.save(drink)
                case .workout(let workout): try await health.save(workout)
                case .weight(let weight): try await health.save(weight)
                }
                // The calories of a workout go to Health only while that type may be written; remember how it was at this moment.
                let energyInHealth: Bool? = if case .workout = unsynced.entry { access.allowsWriting(.activeEnergy) } else { nil }
                if complete { store.markSynced(unsynced.entry.id, version: unsynced.version, energyInHealth: energyInHealth) }
            } catch {
                log(error, while: "save")
            }
        }
        for (id, kind) in store.dueDeletionEntries(now: now()) {
            // The entry came back ("Widerrufen") after the deletion was queued.
            guard !store.exists(id) else {
                store.removeDeletion(id)
                continue
            }
            let reachable = kind == .weight ? bodyAsked : coreOpen
            guard reachable else {
                // Nothing ever reached Health before the user was asked, so such a deletion has nothing to remove there. A denied
                // core group keeps its deletions queued.
                if kind == .weight ? !bodyAsked : !access.wasAsked { store.removeDeletion(id) }
                continue
            }
            do {
                if try await health.deleteEntry(id: id, kind: kind) { store.removeDeletion(id) }
            } catch {
                log(error, while: "delete")
            }
        }
    }

    private func log(_ error: Error, while action: String) {
        let nsError = error as NSError
        logger.error("Health \(action, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code)")
    }
}
