import Foundation

/// One line of an ingredient list, split into amount, unit and name ("250 g rote Linsen"), so a recipe can be
/// scaled to another number of servings. Pure rules; the amount is `nil` for lines without a number.
public struct IngredientLine: Sendable, Hashable {
    /// The amount, or the lower end of a range ("2–3 EL").
    public var amount: Decimal?
    /// The upper end of a range; `nil` for a single amount.
    public var amountUpper: Decimal?
    /// The unit as it was written ("EL", "Dosen"); `nil` for counts ("2 Eier").
    public var unit: String?
    /// The name without amount, unit and parenthesis. Without an amount this is the whole line.
    public var name: String
    /// The text of a parenthesis ("400 ml" in "1 Dose Kokosmilch (400 ml)").
    public var note: String?
    /// "nach Geschmack", "etwas", "to taste": nothing to scale.
    public var isToTaste: Bool

    public init(amount: Decimal? = nil, amountUpper: Decimal? = nil, unit: String? = nil, name: String, note: String? = nil,
                isToTaste: Bool = false) {
        self.amount = amount
        self.amountUpper = amountUpper
        self.unit = unit
        self.name = name
        self.note = note
        self.isToTaste = isToTaste
    }

    // MARK: Units

    /// How a unit is rounded when it is scaled; see `RecipeScaler`.
    enum UnitKind: Sendable, Hashable {
        /// g, ml, mg: whole numbers for small values, then steps of 5 and 10.
        case small
        /// kg, l: tenths.
        case large
        /// EL, TL, Tasse, cup, cl, dl, oz, lb: halves.
        case spoon
        /// Dose, Packung, Becher, can: halves.
        case container
        /// Prise, pinch: never scaled.
        case pinch
        /// Stück, Zehe, Scheibe, Bund, clove, slice, piece: whole numbers, rounded up.
        case count
    }

    struct UnitInfo: Sendable {
        let singular: String
        let plural: String
        let kind: UnitKind
        /// Written forms that denote the unit, lowercased.
        let forms: [String]
    }

    static let units: [UnitInfo] = [
        UnitInfo(singular: "g", plural: "g", kind: .small, forms: ["g"]),
        UnitInfo(singular: "mg", plural: "mg", kind: .small, forms: ["mg"]),
        UnitInfo(singular: "ml", plural: "ml", kind: .small, forms: ["ml"]),
        UnitInfo(singular: "kg", plural: "kg", kind: .large, forms: ["kg"]),
        UnitInfo(singular: "l", plural: "l", kind: .large, forms: ["l"]),
        UnitInfo(singular: "cl", plural: "cl", kind: .spoon, forms: ["cl"]),
        UnitInfo(singular: "dl", plural: "dl", kind: .spoon, forms: ["dl"]),
        UnitInfo(singular: "EL", plural: "EL", kind: .spoon, forms: ["el"]),
        UnitInfo(singular: "TL", plural: "TL", kind: .spoon, forms: ["tl"]),
        UnitInfo(singular: "Tasse", plural: "Tassen", kind: .spoon, forms: ["tasse", "tassen"]),
        UnitInfo(singular: "cup", plural: "cups", kind: .spoon, forms: ["cup", "cups"]),
        UnitInfo(singular: "tbsp", plural: "tbsp", kind: .spoon, forms: ["tbsp"]),
        UnitInfo(singular: "tsp", plural: "tsp", kind: .spoon, forms: ["tsp"]),
        UnitInfo(singular: "oz", plural: "oz", kind: .spoon, forms: ["oz"]),
        UnitInfo(singular: "lb", plural: "lbs", kind: .spoon, forms: ["lb", "lbs"]),
        UnitInfo(singular: "Dose", plural: "Dosen", kind: .container, forms: ["dose", "dosen"]),
        UnitInfo(singular: "Packung", plural: "Packungen", kind: .container, forms: ["packung", "packungen", "pck.", "pck", "pkg."]),
        UnitInfo(singular: "Becher", plural: "Becher", kind: .container, forms: ["becher"]),
        UnitInfo(singular: "can", plural: "cans", kind: .container, forms: ["can", "cans"]),
        UnitInfo(singular: "Prise", plural: "Prisen", kind: .pinch, forms: ["prise", "prisen"]),
        UnitInfo(singular: "pinch", plural: "pinches", kind: .pinch, forms: ["pinch", "pinches"]),
        UnitInfo(singular: "Bund", plural: "Bund", kind: .count, forms: ["bund"]),
        UnitInfo(singular: "Zehe", plural: "Zehen", kind: .count, forms: ["zehe", "zehen"]),
        UnitInfo(singular: "Scheibe", plural: "Scheiben", kind: .count, forms: ["scheibe", "scheiben"]),
        UnitInfo(singular: "Stück", plural: "Stück", kind: .count, forms: ["stück", "stueck", "stk.", "stk"]),
        UnitInfo(singular: "clove", plural: "cloves", kind: .count, forms: ["clove", "cloves"]),
        UnitInfo(singular: "slice", plural: "slices", kind: .count, forms: ["slice", "slices"]),
        UnitInfo(singular: "piece", plural: "pieces", kind: .count, forms: ["piece", "pieces"])
    ]

    static func unitInfo(for written: String) -> UnitInfo? {
        let key = written.lowercased()
        return units.first { $0.forms.contains(key) }
    }

    /// The rounding class of the unit; `nil` for a line without a unit or with an unknown one.
    var unitKind: UnitKind? { unit.flatMap { Self.unitInfo(for: $0)?.kind } }

    // MARK: Parsing

    private static let toTastePhrases = ["nach geschmack", "n. b.", "n.b.", "to taste"]
    private static let toTasteWords: Set<String> = ["etwas", "some"]

    /// Reads a line like "250 g rote Linsen", "1 1/2 EL Öl", "2–3 Zwiebeln", "½ TL Salz" or "Salz nach Geschmack". A line
    /// without a leading number keeps its whole text as the name. The "to taste" marker only counts without an amount.
    public static func parse(_ line: String) -> IngredientLine {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTaste = containsToTaste(trimmed)
        var scanner = QuantityScanner(Array(trimmed))
        guard let quantity = scanner.scan() else {
            return IngredientLine(name: trimmed, isToTaste: toTaste)
        }
        var rest = scanner.remainder
        var unit: String?
        let hasDirectLetters = rest.first?.isLetter == true
        let restTrimmed = rest.trimmingCharacters(in: .whitespaces)
        let firstWord = restTrimmed.prefix { !$0.isWhitespace }
        if !firstWord.isEmpty, unitInfo(for: String(firstWord)) != nil {
            unit = String(firstWord)
            rest = String(restTrimmed.dropFirst(firstWord.count))
        } else if hasDirectLetters {
            // "1a Qualität", "3D-Brille": letters glued to the number that are no unit mean this is no amount.
            return IngredientLine(name: trimmed, isToTaste: toTaste)
        }
        var name = rest.trimmingCharacters(in: .whitespaces)
        var note: String?
        if let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            let inner = name[name.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            note = inner.isEmpty ? nil : inner
            name.removeSubrange(open...close)
            name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ").replacingOccurrences(of: " ,", with: ",")
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        // English "2 cups of flour".
        if unit != nil, name.lowercased().hasPrefix("of ") { name = String(name.dropFirst(3)) }
        return IngredientLine(amount: quantity.lower, amountUpper: quantity.upper, unit: unit, name: name, note: note)
    }

    private static func containsToTaste(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if toTastePhrases.contains(where: { lowered.contains($0) }) { return true }
        let words = lowered.split { !$0.isLetter }.map(String.init)
        return words.contains { toTasteWords.contains($0) }
    }

    // MARK: Formatting

    /// The line written again. The decimal separator follows `locale`; numbers have at most one decimal place and "1,0"
    /// reads "1". A range is written with an en dash.
    public func formatted(locale: Locale) -> String {
        guard amount != nil else { return name }
        var parts = [quantityText(locale: locale)]
        if !name.isEmpty { parts.append(name) }
        if let note { parts.append("(\(note))") }
        return parts.joined(separator: " ")
    }

    /// The amount and the unit alone ("1,5 Dosen"); empty for a line without an amount.
    public func quantityText(locale: Locale) -> String {
        guard let amount else { return "" }
        var text = Self.format(amount, locale: locale)
        if let amountUpper { text += "–" + Self.format(amountUpper, locale: locale) }
        if let unit { text += " " + unit }
        return text
    }

    static func format(_ value: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

/// Reads the number at the start of an ingredient line: "250", "1,5", "1/2", "½", "1 1/2", "1½" and ranges "2-3".
private struct QuantityScanner {
    private let characters: [Character]
    private var index = 0

    init(_ characters: [Character]) { self.characters = characters }

    /// What follows the number.
    var remainder: String { String(characters[index...]) }

    private static let unicodeFractions: [Character: Decimal] = [
        "½": 1 / 2, "¼": 1 / 4, "¾": 3 / 4, "⅓": 1 / 3, "⅔": 2 / 3, "⅛": 1 / 8, "⅜": 3 / 8, "⅝": 5 / 8, "⅞": 7 / 8
    ]

    mutating func scan() -> (lower: Decimal, upper: Decimal?)? {
        guard let lower = number() else { return nil }
        // A range: "2-3", "2 – 3".
        var probe = index
        skipSpaces(&probe)
        if probe < characters.count, "-–—".contains(characters[probe]) {
            probe += 1
            skipSpaces(&probe)
            let saved = index
            index = probe
            if let upper = number(), upper > lower { return (lower, upper) }
            index = saved
        }
        return (lower, nil)
    }

    private func skipSpaces(_ position: inout Int) {
        while position < characters.count, characters[position] == " " { position += 1 }
    }

    private func isDigit(_ position: Int) -> Bool {
        position < characters.count && characters[position].isASCII && characters[position].isNumber
    }

    private func digits(from start: Int) -> (text: String, end: Int) {
        var end = start
        while isDigit(end) { end += 1 }
        return (String(characters[start..<end]), end)
    }

    /// One number at `index`, or `nil`.
    private mutating func number() -> Decimal? {
        guard index < characters.count else { return nil }
        if let fraction = Self.unicodeFractions[characters[index]] {
            index += 1
            return fraction
        }
        guard isDigit(index) else { return nil }
        let whole = digits(from: index)
        var position = whole.end
        // Decimal comma or point: "1,5", "0.25".
        if position + 1 < characters.count, characters[position] == "," || characters[position] == ".", isDigit(position + 1) {
            let fraction = digits(from: position + 1)
            index = fraction.end
            return Decimal(string: whole.text + "." + fraction.text, locale: Locale(identifier: "en_US_POSIX"))
        }
        guard let integer = Decimal(string: whole.text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        // A fraction: "1/2".
        if position + 1 < characters.count, characters[position] == "/", isDigit(position + 1) {
            let denominator = digits(from: position + 1)
            guard let divisor = Decimal(string: denominator.text, locale: Locale(identifier: "en_US_POSIX")), divisor != 0 else { return nil }
            index = denominator.end
            return integer / divisor
        }
        // A mixed number: "1 1/2", "1 ½", "1½".
        skipSpaces(&position)
        if position < characters.count, let fraction = Self.unicodeFractions[characters[position]] {
            index = position + 1
            return integer + fraction
        }
        if isDigit(position) {
            let numerator = digits(from: position)
            if numerator.end + 1 < characters.count, characters[numerator.end] == "/", isDigit(numerator.end + 1) {
                let denominator = digits(from: numerator.end + 1)
                if let top = Decimal(string: numerator.text, locale: Locale(identifier: "en_US_POSIX")),
                   let divisor = Decimal(string: denominator.text, locale: Locale(identifier: "en_US_POSIX")), divisor != 0 {
                    index = denominator.end
                    return integer + top / divisor
                }
            }
        }
        index = whole.end
        return integer
    }
}
