import Foundation

/// One confirmed accessibility audit finding (or a screen that did not settle before its audit) that waits to be reported as a test failure.
struct CollectedAuditFinding: Equatable {
    /// The screen the finding belongs to (the `screen` argument of `AuditAllowlist.audit`).
    let screen: String
    /// The text of the test failure; it starts with the screen.
    let message: String
    /// The call site of `AuditAllowlist.audit`, so the failure points at the screen that was audited.
    let file: String
    let line: Int
}

/// Collects the confirmed findings of the screens a UI test visits, so that one run reports all of them instead of stopping at the first.
///
/// A confirmed finding is a property of one screen; it says nothing about whether the next screen can still be reached. The audit therefore
/// adds it here and the test goes on. The collected findings are reported when the test ends (`UITestCase`), also when it ends early
/// because of a failed navigation step or a thrown error. Failures of navigation and interaction are not collected: they still stop the
/// test at once, because everything after them would be a cascade of meaningless failures.
struct AuditFindingCollector {
    private(set) var findings: [CollectedAuditFinding] = []

    var isEmpty: Bool { findings.isEmpty }

    mutating func add(_ finding: CollectedAuditFinding) {
        findings.append(finding)
    }

    /// The screens that have findings, in the order of their first finding.
    var screens: [String] {
        var seen = Set<String>()
        return findings.map(\.screen).filter { seen.insert($0).inserted }
    }

    /// The compact overview at the end of a failing audit test: a header with the counts and one line per finding; empty without findings.
    var summary: String {
        guard !findings.isEmpty else { return "" }
        let header = "\(findings.count) confirmed audit \(findings.count == 1 ? "finding" : "findings") on "
            + "\(screens.count) \(screens.count == 1 ? "screen" : "screens"):"
        return ([header] + findings.map { "  - \($0.message)" }).joined(separator: "\n")
    }
}
