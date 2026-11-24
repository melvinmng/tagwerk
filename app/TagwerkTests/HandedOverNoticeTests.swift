import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Texts of the capsule after an issue left the task list (GH5c, GH7b).
@MainActor
struct HandedOverNoticeTests {
    private func notice(_ reason: UnlistedReason, assignees: [String] = ["octo"], number: Int = 151) -> HandedOverNotice {
        var item = makeTask("Issue", source: .github)
        item.assignees = assignees
        item.url = URL(string: "https://github.com/beispiel/app/issues/\(number)")
        return HandedOverNotice(item: item, reason: reason)
    }

    private func caption(_ notice: HandedOverNotice) -> String {
        String(localized: notice.caption)
    }

    @Test func handedOver_keepsTheCurrentTexts() {
        let notice = notice(.handedOver, assignees: ["lea-m"])
        #expect(caption(notice) == "Vergeben")
        #expect(notice.title == "#151 an lea-m")
        #expect(notice.announcement == "Vergeben: #151 an lea-m. Auf GitHub öffnen verfügbar.")
    }

    @Test func noProject_alone_saysNotInTasks() {
        let notice = notice(.noProject(others: []))
        #expect(caption(notice) == "Angelegt · nicht in Aufgaben")
        #expect(notice.title == "#151 ohne Projekt")
        #expect(notice.announcement == "Angelegt, nicht in Aufgaben: #151 ohne Projekt. Auf GitHub öffnen verfügbar.")
        #expect(notice.symbol == "tray")
    }

    @Test func noProject_withOthers_namesThem() {
        #expect(notice(.noProject(others: ["lea-m"])).title == "#151 an lea-m · ohne Projekt")
        #expect(notice(.noProject(others: ["lea-m", "sam"])).title == "#151 an lea-m und sam · ohne Projekt")
        #expect(notice(.noProject(others: ["lea-m"])).announcement
            == "Angelegt, nicht in Aufgaben: #151 an lea-m · ohne Projekt. Auf GitHub öffnen verfügbar.")
    }

    @Test func noProject_fromThreePeople_countsThem() {
        #expect(notice(.noProject(others: ["a", "b", "c"])).title == "#151 an 3 Personen · ohne Projekt")
    }

    @Test func doneInSelection_oneProject_namesBothProjects() {
        let notice = notice(.doneInSelection(doneIn: ["Tagwerk"], openIn: ["Roadmap 2027"]), number: 154)
        #expect(caption(notice) == "In „Tagwerk“ erledigt")
        #expect(notice.title == "#154 noch offen in „Roadmap 2027“")
        #expect(notice.announcement == "In Tagwerk erledigt: #154 noch offen in Roadmap 2027. Auf GitHub öffnen verfügbar.")
        #expect(notice.symbol == "checkmark.circle")
    }

    @Test func doneInSelection_severalProjects_countsThem() {
        let notice = notice(.doneInSelection(doneIn: ["Tagwerk", "App"], openIn: ["Roadmap 2027", "Team"]), number: 154)
        #expect(caption(notice) == "In 2 Projekten erledigt")
        #expect(notice.title == "#154 noch offen in 2 Projekten")
        #expect(notice.announcement == "In 2 Projekten erledigt: #154 noch offen in 2 Projekten. Auf GitHub öffnen verfügbar.")
    }

    /// The announcement is read in the language of the app: the English texts carry no German or English quotation marks.
    @Test func doneInSelection_englishAnnouncementHasNoQuotationMarks() {
        let title = Localized.string("\("#154") noch offen in \("Roadmap 2027")", in: .english, bundle: .main)
        #expect(title == "#154 still open in Roadmap 2027")
        let spoken = Localized.string("In \("Tagwerk") erledigt: \(title). Auf GitHub öffnen verfügbar.", in: .english, bundle: .main)
        #expect(spoken == "Done in Tagwerk: #154 still open in Roadmap 2027. Open on GitHub available.")
        // The written form keeps the English quotation marks.
        let written = Localized.string("\("#154") noch offen in „\("Roadmap 2027")“", in: .english, bundle: .main)
        #expect(written == "#154 still open in “Roadmap 2027”")
    }
}
