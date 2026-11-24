import Foundation

/// One finding of an accessibility audit pass that is not on the allowlist.
struct AuditFinding: Equatable {
    /// Identifies the finding in another pass: type, text of the finding and label of the element (not its frame, which moves with the
    /// scroll position).
    let key: String
    /// The text that fails the test.
    let message: String
    /// The Dynamic Type check: the one finding type that changes from pass to pass on the same code (see `AuditConfirmation`).
    let isDynamicType: Bool
}

/// Decides which findings of an audit pass are real.
///
/// A finding is a property of the screen, so it comes back when the pass runs again. One that does not is a measurement of the moment
/// (the audit resizes the text and reads the layout while the runner is busy) and does not fail the test. Every finding type needs two
/// passes to agree, except Dynamic Type at the default size: it named other texts of the same screen from run to run on the same code
/// and, with two passes, still failed about one test in ten (docs/superpowers/plans/2026-11-23-ci-audit-rest.md, sections 3.3 and 3.4),
/// so it needs three. A further pass only runs when the earlier ones reported something, so a clean screen costs nothing.
enum AuditConfirmation {
    static let defaultPasses = 2
    static let dynamicTypePasses = 3

    /// The number of passes that must report `finding` before it fails the test.
    static func requiredPasses(for finding: AuditFinding) -> Int {
        finding.isDynamicType ? dynamicTypePasses : defaultPasses
    }

    enum Outcome: Equatable {
        /// Reported by every pass that was required.
        case confirmed
        /// A later pass did not report it; `passes` is the number of passes that reported it (the first one included).
        case unconfirmed(passes: Int)
    }

    /// Judges the findings of the first pass. `rerun` runs another pass and returns the keys it reported; it is called at most
    /// `dynamicTypePasses - 1` times, and only while a finding is still waiting for confirmation.
    static func judge(_ first: [AuditFinding], rerun: () throws -> Set<String>) rethrows -> [(finding: AuditFinding, outcome: Outcome)] {
        var outcomes: [String: Outcome] = [:]
        var waiting = first
        var passes = 1
        while !waiting.isEmpty {
            let reported = try rerun()
            passes += 1
            var stillWaiting: [AuditFinding] = []
            for finding in waiting {
                if !reported.contains(finding.key) {
                    outcomes[finding.key] = .unconfirmed(passes: passes - 1)
                } else if requiredPasses(for: finding) <= passes {
                    outcomes[finding.key] = .confirmed
                } else {
                    stillWaiting.append(finding)
                }
            }
            waiting = stillWaiting
        }
        return first.map { ($0, outcomes[$0.key] ?? .confirmed) }
    }
}
