import Testing

/// The collection of confirmed audit findings that a UI test reports when it ends (`app/TagwerkUITests/AuditFindingCollector.swift`).
struct AuditFindingCollectorTests {
    private func finding(_ screen: String, _ detail: String) -> CollectedAuditFinding {
        CollectedAuditFinding(screen: screen, message: "\(screen): \(detail)", file: "AuditTests.swift", line: 12)
    }

    @Test func emptyCollector_hasNoSummary() {
        let collector = AuditFindingCollector()
        #expect(collector.isEmpty)
        #expect(collector.summary == "")
        #expect(collector.screens.isEmpty)
    }

    @Test func findings_keepTheOrderInWhichTheyWereAdded() {
        var collector = AuditFindingCollector()
        collector.add(finding("Planen", "contrast"))
        collector.add(finding("Aufgaben", "clipped"))
        #expect(collector.findings.map(\.message) == ["Planen: contrast", "Aufgaben: clipped"])
        #expect(!collector.isEmpty)
    }

    @Test func screens_listEachScreenOnceInTheOrderOfItsFirstFinding() {
        var collector = AuditFindingCollector()
        collector.add(finding("Planen", "contrast"))
        collector.add(finding("Aufgaben", "clipped"))
        collector.add(finding("Planen", "hit region"))
        #expect(collector.screens == ["Planen", "Aufgaben"])
    }

    @Test func summary_countsFindingsAndScreensAndListsEveryFinding() {
        var collector = AuditFindingCollector()
        collector.add(finding("Planen", "contrast"))
        collector.add(finding("Aufgaben", "clipped"))
        collector.add(finding("Planen", "hit region"))
        #expect(collector.summary == """
            3 confirmed audit findings on 2 screens:
              - Planen: contrast
              - Aufgaben: clipped
              - Planen: hit region
            """)
    }

    @Test func summary_ofOneFinding_usesTheSingular() {
        var collector = AuditFindingCollector()
        collector.add(finding("Erfassen", "contrast"))
        #expect(collector.summary == "1 confirmed audit finding on 1 screen:\n  - Erfassen: contrast")
    }
}
