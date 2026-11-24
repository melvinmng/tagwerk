import Testing

/// The rule that decides which findings of the accessibility audit fail a UI test (`app/TagwerkUITests/AuditConfirmation.swift`).
struct AuditConfirmationTests {
    private func finding(_ key: String, dynamicType: Bool = false) -> AuditFinding {
        AuditFinding(key: key, message: "message of \(key)", isDynamicType: dynamicType)
    }

    /// Runs the judgement with the keys that the later passes report, in order; returns the outcomes by key and the number of reruns.
    private func judge(_ first: [AuditFinding], later: [Set<String>]) -> (outcomes: [String: AuditConfirmation.Outcome], reruns: Int) {
        var remaining = later
        var reruns = 0
        let result = AuditConfirmation.judge(first) {
            reruns += 1
            return remaining.isEmpty ? [] : remaining.removeFirst()
        }
        return (Dictionary(uniqueKeysWithValues: result.map { ($0.finding.key, $0.outcome) }), reruns)
    }

    @Test func cleanScreen_runsNoFurtherPass() {
        let result = judge([], later: [["a"]])
        #expect(result.outcomes.isEmpty)
        #expect(result.reruns == 0)
    }

    @Test func otherType_isConfirmedByTwoPasses() {
        let result = judge([finding("clipped")], later: [["clipped"]])
        #expect(result.outcomes["clipped"] == .confirmed)
        #expect(result.reruns == 1)
    }

    @Test func otherType_isDroppedWhenTheSecondPassDoesNotReportIt() {
        let result = judge([finding("clipped")], later: [[]])
        #expect(result.outcomes["clipped"] == .unconfirmed(passes: 1))
        #expect(result.reruns == 1)
    }

    @Test func dynamicType_needsThreePasses() {
        let result = judge([finding("dynamic", dynamicType: true)], later: [["dynamic"], ["dynamic"]])
        #expect(result.outcomes["dynamic"] == .confirmed)
        #expect(result.reruns == 2)
    }

    @Test func dynamicType_reportedByTwoOfThreePasses_isDropped() {
        let result = judge([finding("dynamic", dynamicType: true)], later: [["dynamic"], []])
        #expect(result.outcomes["dynamic"] == .unconfirmed(passes: 2))
        #expect(result.reruns == 2)
    }

    @Test func dynamicType_missingInTheSecondPass_stopsAfterOneRerun() {
        let result = judge([finding("dynamic", dynamicType: true)], later: [[], ["dynamic"]])
        #expect(result.outcomes["dynamic"] == .unconfirmed(passes: 1))
        #expect(result.reruns == 1)
    }

    @Test func mixedFindings_areJudgedEachByItsOwnRule() {
        let first = [finding("clipped"), finding("dynamic", dynamicType: true), finding("gone", dynamicType: true)]
        let result = judge(first, later: [["clipped", "dynamic"], ["dynamic"]])
        #expect(result.outcomes["clipped"] == .confirmed)
        #expect(result.outcomes["dynamic"] == .confirmed)
        #expect(result.outcomes["gone"] == .unconfirmed(passes: 1))
        #expect(result.reruns == 2)
    }

    @Test func otherTypesAlone_neverNeedAThirdPass() {
        let result = judge([finding("a"), finding("b")], later: [["a", "b"], ["a", "b"]])
        #expect(result.reruns == 1)
    }

    @Test func resultKeepsTheOrderOfTheFindings() {
        let first = [finding("b"), finding("a"), finding("c")]
        var rerun = 0
        let result = AuditConfirmation.judge(first) { rerun += 1; return ["a", "b", "c"] }
        #expect(result.map(\.finding.key) == ["b", "a", "c"])
        #expect(rerun == 1)
    }

    @Test func requiredPasses_followTheFindingType() {
        #expect(AuditConfirmation.requiredPasses(for: finding("x")) == 2)
        #expect(AuditConfirmation.requiredPasses(for: finding("x", dynamicType: true)) == 3)
    }
}
