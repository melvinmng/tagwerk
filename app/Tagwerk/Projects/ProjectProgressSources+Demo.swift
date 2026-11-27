import Foundation
import TagwerkCore

extension ProjectProgressSources {
    /// Fixed projects for the UI test mode: no network, no EventKit, and the same numbers on every run (all dates count back from `now`).
    @MainActor
    static func demo(now: @escaping () -> Date) -> ProjectProgressSources {
        let calendar = Calendar.tagwerk
        func ago(_ days: Int, hour: Int = 10) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now())) ?? now()
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        func due(_ days: Int) -> DueDate {
            DueDate(date: calendar.date(byAdding: .day, value: days, to: now()) ?? now(), includeTime: false, calendar: calendar)
        }
        func item(_ id: String, _ title: String, created: Int, closed: Int? = nil, notPlanned: Bool = false, due: DueDate? = nil,
                  status: String? = nil, blockedBy: Int = 0, blocking: Int = 0, number: Int? = nil,
                  estimate: Int? = nil) -> ProjectItemFact {
            ProjectItemFact(id: id, title: title, number: number, createdAt: ago(created), closedAt: closed.map { ago($0) },
                            state: closed == nil ? .open : (notPlanned ? .closedNotPlanned : .completed), due: due, status: status,
                            openBlockedByCount: blockedBy, openBlockingCount: blocking, estimateMinutes: estimate)
        }
        let tagwerk = ProjectProgressReference(kind: .gitHubProject, id: "PVT_demo_tagwerk", title: "Beispiel-Projekt")
        let home = ProjectProgressReference(kind: .remindersList, id: "demo-list-home", title: "Privat & Haushalt")
        let studies = ProjectProgressReference(kind: .remindersList, id: "demo-list-studies", title: "Studium")
        let local = ProjectProgressReference.local(title: "Lokal")
        let items: [String: [ProjectItemFact]] = [
            tagwerk.key: [
                item("t1", "Strichcode-Scan", created: 40, closed: 25, number: 319),
                item("t2", "Wochenrückblick", created: 38, closed: 20, number: 320),
                item("t3", "Suche in Einstellungen", created: 30, closed: 12, number: 331),
                item("t4", "Doppelte Anfrage", created: 28, closed: 27, notPlanned: true, number: 322),
                item("t5", "Projektfortschritt", created: 14, due: due(10), status: "In progress", number: 332, estimate: 240),
                item("t6", "App-Sperre im Fokus-Modus", created: 12, due: due(-3), status: "Blocked", blockedBy: 1, number: 236),
                item("t7", "Zugangsdaten erneuern", created: 11, blocking: 2, number: 240),
                item("t8", "Sprachmodell wechseln", created: 9, due: due(5), status: "Ready", number: 301, estimate: 120),
                item("t9", "Begrüßung überarbeiten", created: 5, closed: 2, number: 338),
                item("t10", "Widget-Größen prüfen", created: 3, status: "Ready", number: 341, estimate: 90),
            ],
            home.key: [
                item("h1", "Steuerunterlagen sortieren", created: 30, closed: 22),
                item("h2", "Fenster putzen", created: 20, closed: 6),
                item("h3", "Versicherung kündigen", created: 9, due: due(-1)),
                item("h4", "Geschenk besorgen", created: 4, due: due(7)),
            ],
            studies.key: [
                item("s1", "Literatur sichten", created: 60, closed: 40),
                item("s2", "Exposé schreiben", created: 45, closed: 30),
                item("s3", "Betreuer anschreiben", created: 40, due: due(-20)),
                item("s4", "Gliederung abstimmen", created: 36),
            ],
            local.key: [
                item("l1", "Kopfhörer reparieren", created: 8, closed: 1),
                item("l2", "Notizen sortieren", created: 2),
            ],
        ]
        let references = [tagwerk, home, studies, local]
        // Time of the demo project "Beispiel-Projekt", all inside the last three weeks and before now, so the numbers are the same
        // on every run: planned 3 h + 2 h + 2 h = 7 h (one block was cut at completion: planned until 12:00, ended 11:00),
        // invested 2 h (the cut block up to the completion of #320) + 1 h + 1 h (two focus sessions) = 4 h.
        func githubKey(_ id: String) -> String { TaskID(source: .github, rawValue: id).key }
        func at(_ days: Int, _ hour: Int) -> Date { ago(days, hour: hour) }
        let timeInputs = ProjectTimeInputs(
            blocks: [
                ProjectTimeBlock(taskKey: githubKey("t2"), start: at(18, 9), end: at(18, 11), plannedEnd: at(18, 12)),
                ProjectTimeBlock(taskKey: githubKey("t5"), start: at(14, 9), end: at(14, 11)),
                ProjectTimeBlock(taskKey: githubKey("t5"), start: at(9, 14), end: at(9, 16)),
            ],
            focus: [
                ProjectFocusSpan(taskKey: githubKey("t5"), start: at(9, 14), end: at(9, 15)),
                ProjectFocusSpan(taskKey: githubKey("t5"), start: at(3, 10), end: at(3, 11)),
            ],
            completions: [ProjectCompletion(taskKey: githubKey("t2"), completedAt: at(18, 11), countsBlocks: true)])
        return ProjectProgressSources(
            catalog: { ProjectCatalog(references: references, gitHubConnected: true, remindersAccess: true) },
            facts: { reference in
                guard let facts = items[reference.key] else { throw ProjectLoadFailure.other }
                return ProjectFactsLoad(facts: facts, fetchedAt: now())
            },
            time: { _, _ in timeInputs })
    }
}
