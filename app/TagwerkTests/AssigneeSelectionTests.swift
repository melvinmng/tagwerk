import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct AssigneeSelectionTests {
    let me = "octo"

    @Test func ordered_putsMeFirstThenAlphabeticalIgnoringCase() {
        #expect(AssigneeSelection.ordered(candidates: ["sam-dev", "Jonas-k", "octo", "lea-m"], me: me)
            == ["octo", "Jonas-k", "lea-m", "sam-dev"])
    }

    @Test func ordered_addsMeWhenGitHubOmitsMe() {
        #expect(AssigneeSelection.ordered(candidates: ["lea-m"], me: me) == ["octo", "lea-m"])
    }

    @Test func ordered_keepsGitHubSpellingOfMe_andDropsDuplicates() {
        #expect(AssigneeSelection.ordered(candidates: ["lea-m", "Octo", "LEA-M"], me: me) == ["Octo", "lea-m"])
        #expect(AssigneeSelection.ordered(candidates: ["b", "a"], me: nil) == ["a", "b"])
    }

    @Test func draftAssignees_untouchedDefaultStaysNil_soTheProviderAssignsTheViewer() {
        // Also while the login is unknown: an empty selection that nobody chose must never become "nobody".
        #expect(AssigneeSelection.draftAssignees(selected: [], chosen: false) == nil)
        #expect(AssigneeSelection.draftAssignees(selected: ["octo"], chosen: false) == nil)
    }

    @Test func draftAssignees_explicitChoiceIsSentAsIs_includingNobody() {
        #expect(AssigneeSelection.draftAssignees(selected: [], chosen: true) == [])
        #expect(AssigneeSelection.draftAssignees(selected: ["lea-m"], chosen: true) == ["lea-m"])
    }

    @Test func value_cases() {
        #expect(AssigneeSelection.value(selected: [], me: me) == "Niemand")
        #expect(AssigneeSelection.value(selected: ["octo"], me: me) == "Ich")
        #expect(AssigneeSelection.value(selected: ["lea-m", "octo"], me: me) == "Ich, lea-m")
        #expect(AssigneeSelection.value(selected: ["lea-m"], me: me) == "lea-m")
        #expect(AssigneeSelection.value(selected: ["lea-m", "octo", "sam"], me: me) == "3 Personen")
    }

    @Test func label_marksMe() {
        #expect(AssigneeSelection.label("octo", me: me) == "Ich (octo)")
        #expect(AssigneeSelection.label("Octo", me: me) == "Ich (Octo)")
        #expect(AssigneeSelection.label("lea-m", me: me) == "lea-m")
        #expect(AssigneeSelection.label("lea-m", me: nil) == "lea-m")
    }

    @Test func footer_cases() {
        #expect(AssigneeSelection.footer(selected: ["octo"], me: me) == "Das Issue wird dir zugewiesen.")
        #expect(AssigneeSelection.footer(selected: ["octo", "lea-m"], me: me) == "Das Issue wird dir und lea-m zugewiesen.")
        #expect(AssigneeSelection.footer(selected: ["octo", "a", "b", "c", "d"], me: me)
            == "Das Issue wird dir und 4 weiteren Personen zugewiesen.")
        #expect(AssigneeSelection.footer(selected: ["lea-m"], me: me)
            == "Das Issue wird lea-m zugewiesen und erscheint danach nicht in deinen Aufgaben.")
        #expect(AssigneeSelection.footer(selected: [], me: me)
            == "Das Issue wird niemandem zugewiesen und erscheint danach nicht in deinen Aufgaben.")
    }

    @Test func footer_twoOthers_usesOneList() {
        #expect(AssigneeSelection.footer(selected: ["lea-m", "octo", "jonas-k"], me: me)
            == "Das Issue wird dir, jonas-k und lea-m zugewiesen.")
    }

    @Test func footer_threeOthersWithoutMe_namesTheCount() {
        #expect(AssigneeSelection.footer(selected: ["a", "b", "c"], me: me)
            == "Das Issue wird 3 Personen zugewiesen und erscheint danach nicht in deinen Aufgaben.")
    }

    @Test func names_withoutSummary_listsEveryLogin() {
        #expect(AssigneeSelection.names(selected: ["a", "octo", "b", "c"], me: me, summarize: false) == "dir, a, b und c")
        #expect(AssigneeSelection.names(selected: ["octo", "lea-m"], me: me, summarize: false, language: .english) == "you and lea-m")
    }

    @Test func capsuleTitle_cases() {
        #expect(AssigneeSelection.capsuleTitle(number: 151, assignees: ["lea-m"]) == "#151 an lea-m")
        #expect(AssigneeSelection.capsuleTitle(number: 151, assignees: ["lea-m", "jonas-k"]) == "#151 an lea-m und jonas-k")
        #expect(AssigneeSelection.capsuleTitle(number: 151, assignees: ["a", "b", "c"]) == "#151 an 3 Personen")
        #expect(AssigneeSelection.capsuleTitle(number: 151, assignees: []) == "#151 ohne Zuweisung")
        #expect(AssigneeSelection.capsuleTitle(number: nil, assignees: ["lea-m"]) == "Issue an lea-m")
    }

    @Test func handedOverAnnouncement_namesNumberAndPeople() {
        #expect(AssigneeSelection.announcement(number: 151, assignees: ["lea-m"])
            == "Vergeben: #151 an lea-m. Auf GitHub öffnen verfügbar.")
        #expect(AssigneeSelection.announcement(number: 151, assignees: [])
            == "Vergeben: #151 ohne Zuweisung. Auf GitHub öffnen verfügbar.")
    }

    @Test func canAdd_stopsAtTen() {
        #expect(AssigneeSelection.canAdd(selectedCount: 9))
        #expect(!AssigneeSelection.canAdd(selectedCount: 10))
    }
}

struct AssigneeLoadTests {
    @Test func staleResultIsDiscarded() {
        #expect(AssigneeLoad.loading(repository: "a/x").adopting(["lea-m"], for: "a/x", selected: "a/y")
            == .loading(repository: "a/x"))
    }

    @Test func matchingResultIsAdopted() {
        #expect(AssigneeLoad.loading(repository: "a/x").adopting(["lea-m"], for: "a/x", selected: "a/x")
            == .loaded(repository: "a/x", logins: ["lea-m"]))
    }

    @Test func nilResultFails() {
        #expect(AssigneeLoad.loading(repository: "a/x").adopting(nil, for: "a/x", selected: "a/x") == .failed(repository: "a/x"))
    }

    @Test func logins_onlyForTheSelectedRepository() {
        let load = AssigneeLoad.loaded(repository: "a/x", logins: ["lea-m"])
        #expect(load.logins(for: "a/x") == ["lea-m"])
        #expect(load.logins(for: "a/y") == [])
        #expect(AssigneeLoad.failed(repository: "a/x").logins(for: "a/x") == [])
    }

    @Test func noProjectTitle_onlyMe_hasNoPerson() {
        #expect(AssigneeSelection.noProjectTitle(number: 151, others: []) == "#151 ohne Projekt")
        #expect(AssigneeSelection.noProjectTitle(number: nil, others: []) == "Issue ohne Projekt")
    }

    @Test func noProjectTitle_withOthers_namesThem() {
        #expect(AssigneeSelection.noProjectTitle(number: 151, others: ["lea-m"]) == "#151 an lea-m · ohne Projekt")
        #expect(AssigneeSelection.noProjectTitle(number: 151, others: ["a", "b", "c"]) == "#151 an 3 Personen · ohne Projekt")
    }

    @Test func openElsewhereTitle_namesTheProjectOrCountsThem() {
        #expect(AssigneeSelection.openElsewhereTitle(number: 154, openIn: ["Roadmap 2027"]) == "#154 noch offen in „Roadmap 2027“")
        #expect(AssigneeSelection.openElsewhereTitle(number: 154, openIn: ["A", "B"]) == "#154 noch offen in 2 Projekten")
        #expect(AssigneeSelection.openElsewhereTitle(number: nil, openIn: ["A"]) == "Issue noch offen in „A“")
        // The spoken form has no quotation marks, whatever language the quotes of the written form belong to.
        #expect(AssigneeSelection.openElsewhereTitle(number: 154, openIn: ["Roadmap 2027"], quoted: false) == "#154 noch offen in Roadmap 2027")
        #expect(AssigneeSelection.openElsewhereTitle(number: 154, openIn: ["A", "B"], quoted: false) == "#154 noch offen in 2 Projekten")
    }
}
