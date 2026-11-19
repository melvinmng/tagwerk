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
}
