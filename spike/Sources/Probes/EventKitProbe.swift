import EventKit
import Foundation

/// Verifies read and write access to Reminders and read access to Calendar via EventKit.
struct EventKitProbe: Probe {
    let name = "Reminders & Kalender"

    static func isSufficient(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    static func describe(status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: return "Vollzugriff"
        case .writeOnly: return "nur Hinzufügen erlaubt (Vollzugriff nötig)"
        case .denied: return "Zugriff verweigert (Einstellungen → Datenschutz)"
        case .restricted: return "Zugriff eingeschränkt (z. B. Bildschirmzeit)"
        case .notDetermined: return "noch nicht gefragt"
        @unknown default: return "unbekannter Status"
        }
    }

    func run() async -> ProbeResult {
        let store = EKEventStore()
        do {
            _ = try await store.requestFullAccessToReminders()
            _ = try await store.requestFullAccessToEvents()
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Anfrage fehlgeschlagen: \(error.localizedDescription)")
        }

        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        guard Self.isSufficient(reminderStatus), Self.isSufficient(eventStatus) else {
            return ProbeResult(
                name: name, ok: false,
                detail: "Reminders: \(Self.describe(status: reminderStatus)); Kalender: \(Self.describe(status: eventStatus))"
            )
        }

        let openReminderCount = await countOpenReminders(in: store)
        let todayEventCount = countTodayEvents(in: store)

        do {
            try writeRoundTrip(in: store)
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Lesen ok, Schreiben fehlgeschlagen: \(error.localizedDescription)")
        }

        return ProbeResult(
            name: name, ok: true,
            detail: "\(openReminderCount) offene Erinnerungen, \(todayEventCount) Termine heute, Schreiben ok"
        )
    }

    private func countOpenReminders(in store: EKEventStore) async -> Int {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.count ?? 0)
            }
        }
    }

    private func countTodayEvents(in store: EKEventStore) -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).count
    }

    /// Creates, completes and deletes a temporary reminder. Deletion always runs.
    private func writeRoundTrip(in store: EKEventStore) throws {
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw ProbeError.noDefaultReminderList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Tagwerk-Spike Test"
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
        defer { try? store.remove(reminder, commit: true) }

        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }
}

enum ProbeError: LocalizedError {
    case noDefaultReminderList

    var errorDescription: String? {
        switch self {
        case .noDefaultReminderList: return "Keine Standardliste für Erinnerungen gefunden"
        }
    }
}
