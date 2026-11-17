import Foundation
import Testing
@testable import TagwerkCore

struct LinkResolverTests {
    private func event(_ id: String, _ title: String, url: URL? = nil) -> CalendarEvent {
        CalendarEvent(id: id, externalID: nil, calendarID: "c", title: title, start: .now, end: .now,
                      isAllDay: false, url: url, isBusy: true, version: "1")
    }

    private func issue(_ id: String, number: Int, title: String = "Issue") -> TaskItem {
        var item = makeItem(title, source: .github)
        item = TaskItem(id: TaskID(source: .github, rawValue: id), title: title, notes: nil, due: nil, priority: nil,
                        estimateMinutes: nil, isCompleted: false, container: item.container,
                        url: URL(string: "https://github.com/beispiel/app/issues/\(number)"), version: "1", editableFields: [])
        return item
    }

    @Test func resolve_urlWins() {
        let target = TaskID(source: .local, rawValue: "L1")
        let links = resolveLinks(events: [event("e", "#42 Login", url: TaskLinkURL.make(target))],
                                 tasks: [issue("I_42", number: 42)], manual: [:])
        #expect(links == [ResolvedLink(eventID: "e", taskID: target, origin: .url)])
    }

    @Test func resolve_manualBeforeAutomatic() {
        let manual = TaskID(source: .reminders, rawValue: "R1")
        let links = resolveLinks(events: [event("e", "#42 Login")], tasks: [issue("I_42", number: 42)], manual: ["e": manual])
        #expect(links == [ResolvedLink(eventID: "e", taskID: manual, origin: .manual)])
    }

    @Test func resolve_issueNumberUnique() {
        let links = resolveLinks(events: [event("e", "#42 Login-Fehler beheben")], tasks: [issue("I_42", number: 42)], manual: [:])
        #expect(links == [ResolvedLink(eventID: "e", taskID: TaskID(source: .github, rawValue: "I_42"), origin: .automatic)])
    }

    @Test func resolve_issueNumberAmbiguous_noLink() {
        let links = resolveLinks(events: [event("e", "#42 Login")],
                                 tasks: [issue("I_a", number: 42), issue("I_b", number: 42)], manual: [:])
        #expect(links.isEmpty)
    }

    @Test func resolve_exactReminderTitle() {
        let reminder = makeItem("Kapitel 2  gliedern", source: .reminders)
        let links = resolveLinks(events: [event("e", "kapitel 2 gliedern")], tasks: [reminder], manual: [:])
        #expect(links == [ResolvedLink(eventID: "e", taskID: reminder.id, origin: .automatic)])
    }

    @Test func resolve_ambiguousTitle_noLink() {
        let links = resolveLinks(events: [event("e", "Einkaufen")],
                                 tasks: [makeItem("Einkaufen", source: .reminders), makeItem("Einkaufen", source: .local)],
                                 manual: [:])
        #expect(links.isEmpty)
    }
}
