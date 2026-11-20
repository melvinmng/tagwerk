import Foundation

/// Scales the amounts of a recipe to another number of servings and rounds them the way a cook measures.
public enum RecipeScaler {
    /// The line for `target` servings of a recipe written for `base`. Lines without an amount, "to taste" lines and
    /// pinches stay as they are, as does a base or target below 1 or equal servings. The unit and a few counted names
    /// ("Ei" → "Eier", "Dose" → "Dosen") follow the new amount.
    public static func scale(_ line: IngredientLine, from base: Int, to target: Int) -> IngredientLine {
        guard base > 0, target > 0, base != target, !line.isToTaste, let amount = line.amount else { return line }
        // "1 große Dose": the container is part of the name, so it is rounded like a unit.
        let kind = line.unitKind ?? (line.unit == nil ? nameContainerKind(line.name) : nil)
        if kind == .pinch { return line }
        let factor = Decimal(target) / Decimal(base)
        var scaled = line
        scaled.amount = rounded(amount * factor, kind: kind)
        scaled.amountUpper = line.amountUpper.map { rounded($0 * factor, kind: kind) }
        // A range that collapsed to one value is a single amount now.
        if let upper = scaled.amountUpper, let lower = scaled.amount, upper <= lower { scaled.amountUpper = nil }
        let shown = scaled.amountUpper ?? scaled.amount ?? 1
        if let unit = line.unit, let info = IngredientLine.unitInfo(for: unit) {
            scaled.unit = shown == 1 ? info.singular : info.plural
        } else if line.unit == nil || kind == .count {
            scaled.name = adjustedName(line.name, singular: shown == 1)
        }
        return scaled
    }

    /// Scales the free quantity text of an import ("500 g", "2 Dosen"); `nil` stays `nil`, and text that holds no amount
    /// ("nach Geschmack") is returned unchanged.
    public static func scale(_ quantity: String?, from base: Int, to target: Int, locale: Locale) -> String? {
        guard let quantity else { return nil }
        let marker = "x"
        let line = IngredientLine.parse("\(quantity) \(marker)")
        guard line.amount != nil else { return quantity }
        let scaled = scale(line, from: base, to: target)
        guard scaled != line else { return quantity }
        let text = scaled.formatted(locale: locale)
        guard text.hasSuffix(" " + marker) else { return quantity }
        return String(text.dropLast(marker.count + 1))
    }

    // MARK: Rounding

    private static func nameContainerKind(_ name: String) -> IngredientLine.UnitKind? {
        let isContainer = name.split(whereSeparator: { !$0.isLetter }).contains {
            IngredientLine.unitInfo(for: String($0))?.kind == .container
        }
        return isContainer ? .container : nil
    }

    private static func rounded(_ value: Decimal, kind: IngredientLine.UnitKind?) -> Decimal {
        switch kind {
        case .small:
            // Below 10 whole numbers, up to 1000 steps of 5 (250 g × 1.5 stays 375 g), above that steps of 10.
            if value < 10 { return round(value, step: 1) }
            return round(value, step: value < 1000 ? 5 : 10)
        case .large: return round(value, step: Decimal(string: "0.1")!)
        case .spoon, .container: return round(value, step: Decimal(string: "0.5")!)
        case .pinch: return value
        case .count, nil: return max(1, roundUp(value))
        }
    }

    private static func round(_ value: Decimal, step: Decimal) -> Decimal {
        var quotient = value / step
        var result = Decimal()
        NSDecimalRound(&result, &quotient, 0, .plain)
        return max(step, result * step)
    }

    private static func roundUp(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .up)
        return result
    }

    // MARK: Names

    /// Singular and plural of the names that are counted without a unit.
    private static let nameForms: [(singular: String, plural: String)] = [
        ("Ei", "Eier"), ("Zwiebel", "Zwiebeln"), ("Dose", "Dosen"), ("Zehe", "Zehen"),
        ("egg", "eggs"), ("can", "cans"), ("clove", "cloves")
    ]

    /// Puts the words of `name` that are in the list into the singular or the plural, keeping their first letter's case.
    private static func adjustedName(_ name: String, singular: Bool) -> String {
        name.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let token = String(word)
            let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            for form in nameForms {
                let from = singular ? form.plural : form.singular
                let to = singular ? form.singular : form.plural
                if stripped.lowercased() == from.lowercased() {
                    let replacement = stripped.first?.isUppercase == true ? to.prefix(1).uppercased() + to.dropFirst() : to
                    return token.replacingOccurrences(of: stripped, with: replacement)
                }
            }
            return token
        }.joined(separator: " ")
    }
}
