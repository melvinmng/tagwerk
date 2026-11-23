import Foundation

/// A sliding-window limit on requests: at most `limit` requests in the last `window` seconds. A request that is refused uses no slot.
public struct RequestLimiter: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case allowed
        /// Seconds until a slot is free again, rounded up to whole seconds.
        case wait(TimeInterval)
    }

    public let limit: Int
    public let window: TimeInterval
    private var timestamps: [Date] = []

    public init(limit: Int, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    /// Whether a request at `now` would pass, without using a slot.
    public func decision(at now: Date) -> Decision {
        let recent = timestamps.filter { now.timeIntervalSince($0) < window }
        guard recent.count >= limit, let oldest = recent.min() else { return .allowed }
        return .wait(max(1, (oldest.addingTimeInterval(window).timeIntervalSince(now)).rounded(.up)))
    }

    /// Takes a slot when one is free. A refusal changes nothing.
    public mutating func attempt(at now: Date) -> Decision {
        let result = decision(at: now)
        if result == .allowed {
            timestamps = timestamps.filter { now.timeIntervalSince($0) < window }
            timestamps.append(now)
        }
        return result
    }
}

/// The rules of the online search in Open Food Facts: the request limits of the operator, the contact address in the request header
/// and the mapping of a product to a food.
public enum ProductSearchRules {
    /// Searches per minute and user (operator's rule: 10 search requests per minute).
    public static let searchLimit = 10
    /// Product lookups per minute and user (operator's rule: 15 product requests per minute).
    public static let productLimit = 15
    /// The window of both limits.
    public static let window: TimeInterval = 60
    /// Searches with fewer characters are not sent.
    public static let minimumQueryLength = 3

    public static func makeSearchLimiter() -> RequestLimiter { RequestLimiter(limit: searchLimit, window: window) }
    public static func makeProductLimiter() -> RequestLimiter { RequestLimiter(limit: productLimit, window: window) }

    // MARK: Contact address

    /// What the user entered as the contact address, trimmed; `nil` when it is empty or not a plain e-mail address.
    ///
    /// The address goes into a request header, so it must not hold anything but the characters of a plain address: no space, no
    /// line break, no brackets or quotes. One "@", a local part and a domain with at least one dot.
    public static func validContact(_ entered: String?) -> String? {
        guard let entered else { return nil }
        let text = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 254, text.range(of: pattern, options: .regularExpression) == text.startIndex..<text.endIndex else { return nil }
        return text
    }

    private static let pattern = "[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+"

    /// What happens to the stored address when the user commits the field.
    public enum ContactChange: Sendable, Equatable {
        /// The field is empty: the address is removed and the online search switches off.
        case cleared
        /// A valid address: stored (trimmed).
        case accepted(String)
        /// Not an address: nothing changes, the user is told.
        case invalid
    }

    public static func contactChange(entered: String) -> ContactChange {
        let text = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .cleared }
        if let valid = validContact(text) { return .accepted(valid) }
        return .invalid
    }

    /// `Tagwerk/<version> (<contact>)`; `nil` without a valid address, so no request can be built without one.
    public static func userAgent(version: String, contact: String?) -> String? {
        guard let contact = validContact(contact) else { return nil }
        let cleanVersion = version.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return "Tagwerk/\(cleanVersion.isEmpty ? "0" : cleanVersion) (\(contact))"
    }
}
