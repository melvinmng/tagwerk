import Foundation
import Testing
@testable import TagwerkCore

struct AssigneeRulesTests {
    @Test func missing_reportsDroppedLoginsInRequestOrder() {
        #expect(AssigneeRules.missing(requested: ["lea-m", "Jonas-K", "sam"], actual: ["jonas-k"]) == ["lea-m", "sam"])
    }

    @Test func missing_withoutRequest_isEmpty() {
        #expect(AssigneeRules.missing(requested: nil, actual: []) == [])
    }

    @Test func change_isNilForSameSetIgnoringCaseAndOrder() {
        #expect(AssigneeRules.change(original: ["Octo", "lea-m"], edited: ["lea-m", "octo"]) == nil)
    }

    @Test func change_listsAddAndRemove() {
        #expect(AssigneeRules.change(original: ["octo", "lea-m"], edited: ["lea-m", "sam"])
            == AssigneeChange(add: ["sam"], remove: ["octo"]))
    }

    @Test func change_nilToEmpty_isNil() {
        #expect(AssigneeRules.change(original: nil, edited: []) == nil)
    }

    @Test func applying_keepsLoginsAddedMeanwhile() {
        let change = AssigneeChange(add: ["sam"], remove: ["octo"])
        #expect(AssigneeRules.applying(change, to: ["octo", "lea-m", "new"]) == ["lea-m", "new", "sam"])
    }

    @Test func applying_doesNotDuplicateAnAlreadyAssignedLogin() {
        #expect(AssigneeRules.applying(AssigneeChange(add: ["LEA-M"]), to: ["lea-m"]) == ["lea-m"])
    }

    @Test func canonical_returnsGitHubSpelling() {
        #expect(AssigneeRules.canonical("LEA-M", in: ["jonas-k", "lea-m"]) == "lea-m")
        #expect(AssigneeRules.canonical("ghost", in: ["jonas-k", "lea-m"]) == nil)
    }

    @Test func contains_ignoresCase() {
        #expect(AssigneeRules.contains(["Melvinmng"], "melvinmng"))
        #expect(!AssigneeRules.contains(nil, "melvinmng"))
    }
}
