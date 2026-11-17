/// Task priority P1 (highest) to P5 (lowest).
public enum Priority: Int, CaseIterable, Comparable, Sendable, Codable {
    case p1 = 1, p2, p3, p4, p5

    public var label: String { "P\(rawValue)" }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}
