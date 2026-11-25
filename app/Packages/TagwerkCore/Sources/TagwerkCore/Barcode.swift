import Foundation

/// Rules for the numbers under a product barcode (GTIN: EAN-8, UPC-A, EAN-13, GTIN-14). Pure functions, so the scanner and the manual
/// entry share one check, and a misread code is rejected before anything is looked up or sent.
public enum Barcode {
    /// The lengths of a GTIN: EAN-8, UPC-A, EAN-13 and GTIN-14.
    private static let validLengths: Set<Int> = [8, 12, 13, 14]
    private static let separators: Set<Character> = [" ", "-", "\t", "\n", "\r"]

    /// The digits of a valid barcode, or `nil` for anything else. Spaces and dashes are dropped, so a number typed in groups
    /// ("4 008400 404127") works. The length must be 8, 12, 13 or 14 and the check digit must match.
    public static func normalized(_ text: String) -> String? {
        let digits = text.filter { !separators.contains($0) }
        guard validLengths.contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return hasValidCheckDigit(digits) ? digits : nil
    }

    /// A key that is the same for the same product however the number was written: a UPC-A code and the EAN-13 code with a leading zero
    /// are one product. `nil` for an invalid code.
    public static func comparisonKey(_ text: String) -> String? {
        guard let digits = normalized(text) else { return nil }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }

    /// The GTIN check digit: counted from the right (without the check digit itself) the digits weigh 3, 1, 3, 1, …; the sum plus the
    /// check digit is a multiple of 10.
    private static func hasValidCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard let check = values.last else { return false }
        let weighted = values.dropLast().reversed().enumerated().reduce(0) { sum, entry in
            sum + entry.element * (entry.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - weighted % 10) % 10 == check
    }
}
