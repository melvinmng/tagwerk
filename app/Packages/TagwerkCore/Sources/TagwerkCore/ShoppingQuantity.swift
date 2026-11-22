import Foundation

/// Adds the quantity of a recipe ingredient to the quantity of the same item on the shopping list (EK4b). Pure rules; the
/// quantities are the free texts of the list ("2", "200 g", "1 Prise"), read with the parser of `IngredientLine`.
public enum ShoppingQuantity {
    /// What happens when an ingredient is put on the list although an open item of that name is there already.
    public enum Merge: Equatable, Sendable {
        /// The quantities add up: the quantity of the item becomes this text.
        case raise(to: String)
        /// The quantities cannot be added ("1 Prise" and "2"): the item stays as it is and a second entry is made.
        case secondEntry
        /// The recipe names no quantity: there is nothing to add, the item stays as it is.
        case keep
    }

    /// The sum of two quantities when both are plain numbers or carry the same unit ("2" + "1" → "3", "200 g" + "125 g" →
    /// "325 g", "1 Dose" + "2 Dosen" → "3 Dosen"); `nil` when they cannot be added: different units, a unit on one side only,
    /// ranges ("2–3"), free text ("nach Geschmack") or no quantity in the recipe. An item on the list without a quantity takes
    /// the quantity of the recipe, as it is written. The decimal separator of the result follows `locale`.
    public static func sum(_ existing: String?, _ added: String?, locale: Locale) -> String? {
        guard let addedText = trimmed(added) else { return nil }
        guard let existingText = trimmed(existing) else { return addedText }
        guard let addedPart = part(of: addedText), let existingPart = part(of: existingText) else { return nil }

        let total = existingPart.amount + addedPart.amount
        let number = IngredientLine.format(total, locale: locale)
        switch (existingPart.unit, addedPart.unit) {
        case (nil, nil):
            // Counts of one thing ("2 Zwiebeln" and "1 Zwiebeln") add up only under the same name; without a name they are plain numbers.
            if existingPart.name.isEmpty && addedPart.name.isEmpty { return number }
            guard !existingPart.name.isEmpty, existingPart.name.lowercased() == addedPart.name.lowercased() else { return nil }
            return number + " " + existingPart.name
        case let (existingUnit?, addedUnit?):
            guard existingPart.name.isEmpty, addedPart.name.isEmpty,
                  let firstInfo = IngredientLine.unitInfo(for: existingUnit), let secondInfo = IngredientLine.unitInfo(for: addedUnit),
                  firstInfo.singular == secondInfo.singular else { return nil }
            return number + " " + (total == 1 ? firstInfo.singular : firstInfo.plural)
        default:
            return nil
        }
    }

    /// What putting `added` on a list that holds `existing` does: raise, make a second entry, or nothing. An item whose notes
    /// hold more than the quantity line (`hasLongNotes`) is never overwritten, so it gets a second entry instead of a raise.
    public static func merge(existing: String?, added: String?, hasLongNotes: Bool = false, locale: Locale) -> Merge {
        guard trimmed(added) != nil else { return .keep }
        guard let total = sum(existing, added, locale: locale), !hasLongNotes else { return .secondEntry }
        return .raise(to: total)
    }

    // MARK: Reading

    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The amount, unit and name of a text that is one plain quantity; `nil` for ranges, "nach Geschmack" and lines with a note.
    private static func part(of text: String) -> (amount: Decimal, unit: String?, name: String)? {
        let line = IngredientLine.parse(text)
        guard let amount = line.amount, line.amountUpper == nil, line.note == nil, !line.isToTaste else { return nil }
        return (amount, line.unit, line.name)
    }
}
