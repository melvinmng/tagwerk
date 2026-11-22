import Foundation

/// The biological sex as the resting energy formula (Mifflin–St Jeor) uses it. Health knows more values (other, not set); those
/// have no constant in the formula and are left out, so the value is `nil` there and the user types it in.
public enum FormulaSex: String, Sendable, Codable, CaseIterable, Hashable {
    case female, male
}
