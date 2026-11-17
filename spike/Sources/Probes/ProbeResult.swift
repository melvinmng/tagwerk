import Foundation

/// Outcome of a single feasibility check, shown as one row in the UI.
struct ProbeResult: Sendable, Identifiable {
    let name: String
    let ok: Bool
    let detail: String

    var id: String { name }
}

/// A feasibility check that can run independently of the others.
protocol Probe: Sendable {
    var name: String { get }
    func run() async -> ProbeResult
}
