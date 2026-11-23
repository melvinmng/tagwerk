import Foundation

/// The amount a food's values refer to (decision LM4b).
public enum FoodReference: Sendable, Hashable, Codable {
    /// Values per 100 g; the amount is typed in grams.
    case per100g
    /// Values per 100 ml; the amount is typed in millilitres.
    case per100ml
    /// Values per piece; the amount is a number of pieces. `grams` is the weight of one piece when known.
    case perPiece(grams: Double?)

    private enum CodingKeys: String, CodingKey { case kind, grams }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "per100ml": self = .per100ml
        case "perPiece": self = .perPiece(grams: try container.decodeIfPresent(Double.self, forKey: .grams))
        default: self = .per100g
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storageKind, forKey: .kind)
        if case .perPiece(let grams?) = self { try container.encode(grams, forKey: .grams) }
    }

    /// The stable name used in storage and in the backup.
    public var storageKind: String {
        switch self {
        case .per100g: "per100g"
        case .per100ml: "per100ml"
        case .perPiece: "perPiece"
        }
    }

    /// The reference from its stored parts; an unknown name reads as per 100 g.
    public init(storageKind: String, pieceGrams: Double?) {
        switch storageKind {
        case "per100ml": self = .per100ml
        case "perPiece": self = .perPiece(grams: pieceGrams)
        default: self = .per100g
        }
    }

    /// The weight of one piece; `nil` for the other references.
    public var pieceGrams: Double? {
        if case .perPiece(let grams) = self { return grams }
        return nil
    }

    /// "je 100 g", "je 100 ml", "je Stück (45 g)".
    public func text(locale: Locale = .current) -> String {
        switch self {
        case .per100g: String(localized: "je 100 g", bundle: .module)
        case .per100ml: String(localized: "je 100 ml", bundle: .module)
        case .perPiece(let grams):
            if let grams {
                String(localized: "je Stück (\(FoodValue.number(grams, locale: locale)) g)", bundle: .module)
            } else {
                String(localized: "je Stück", bundle: .module)
            }
        }
    }

    /// The unit of the typed amount: "g", "ml" or "Stück".
    public var amountUnit: String {
        switch self {
        case .per100g: "g"
        case .per100ml: "ml"
        case .perPiece: String(localized: "Stück", bundle: .module)
        }
    }

    /// The amount a new entry starts with: 100 g, 100 ml or 1 piece.
    public var defaultAmount: Double {
        if case .perPiece = self { return 1 }
        return 100
    }
}

/// Where the values of an own food come from.
public enum FoodOrigin: String, Sendable, Codable, CaseIterable, Hashable {
    /// Typed by hand.
    case typed
    /// Read from a photographed nutrition table and confirmed by the user.
    case label
    /// Taken over from an estimated meal item.
    case estimate
    /// Taken over from a product of Open Food Facts (a third-party source).
    case openFoodFacts
}

/// An entry of "Meine Lebensmittel": values per 100 g, per 100 ml or per piece (decision LM1b, LM4b).
///
/// A missing value is unknown, never 0. Products found online are kept apart from the typed values: taking one over creates a
/// separate food with `origin == .openFoodFacts` and a `sourceNote`.
public struct FoodValue: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var reference: FoodReference
    /// Energy per reference amount.
    public var kcal: Double
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    /// Fibre, sugar, saturated fat and salt per reference amount.
    public var nutrients: NutrientValues
    public var origin: FoodOrigin
    /// The barcode of a packaged product, when known.
    public var barcode: String?
    /// Where foreign data comes from, e.g. "Open Food Facts, abgerufen am 21.11.2026".
    public var sourceNote: String?

    public init(id: UUID = UUID(), name: String, reference: FoodReference, kcal: Double, protein: Double? = nil, carbs: Double? = nil,
                fat: Double? = nil, nutrients: NutrientValues = .unknown, origin: FoodOrigin = .typed, barcode: String? = nil,
                sourceNote: String? = nil) {
        self.id = id
        self.name = name
        self.reference = reference
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.nutrients = nutrients
        self.origin = origin
        self.barcode = barcode
        self.sourceNote = sourceNote
    }

    /// A food needs a name and a non-negative energy value.
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kcal >= 0 }

    /// At least one of the macronutrients or further nutrients has no value.
    public var hasGaps: Bool { protein == nil || carbs == nil || fat == nil || Nutrient.allCases.contains { nutrients[$0] == nil } }

    // MARK: Portions

    /// The factor that turns the values per reference amount into the values of `amount`: 250 g of a food per 100 g is 2.5.
    public func scale(forAmount amount: Double) -> Double {
        switch reference {
        case .per100g, .per100ml: amount / 100
        case .perPiece: amount
        }
    }

    /// "250 g", "330 ml", "2 Stück".
    public func amountText(_ amount: Double, locale: Locale = .current) -> String {
        "\(Self.number(amount, locale: locale)) \(reference.amountUnit)"
    }

    /// The item of a meal for `amount` (grams, millilitres or pieces, as the reference says).
    ///
    /// The values are exact: they come from a table, so minimum, value and maximum are equal and the item is not an estimate.
    /// The quantity factor stays 1; the amount is already in the values. The item has no macros of a food that does not state
    /// them: an item holds numbers, not unknowns, for protein, carbohydrates and fat (as for a typed meal), and Health only
    /// receives values above 0. Fibre, sugar, saturated fat and salt stay unknown when the food does not know them.
    public func item(amount: Double, locale: Locale = .current) -> MealItem {
        let factor = scale(forAmount: amount)
        let energy = kcal * factor
        return MealItem(name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: amountText(amount, locale: locale),
                        factor: 1, kcalMin: energy, kcal: energy, kcalMax: energy, protein: (protein ?? 0) * factor,
                        carbs: (carbs ?? 0) * factor, fat: (fat ?? 0) * factor, fiber: nutrients.fiber.map { $0 * factor },
                        sugar: nutrients.sugar.map { $0 * factor }, saturatedFat: nutrients.saturatedFat.map { $0 * factor },
                        salt: nutrients.salt.map { $0 * factor }, isEstimated: false)
    }

    /// The food that results from saving one item of a meal as a food, with the values of the whole item per piece
    /// (`FoodReference.perPiece`). The values of the item include its quantity factor, so what the meal shows is what the food holds. An estimate loses its
    /// range and becomes exact only when the user confirms it in the edit sheet; the origin records where it came from.
    public static func fromItem(_ item: MealItem) -> FoodValue {
        let factor = item.factor
        return FoodValue(name: item.name, reference: .perPiece(grams: nil), kcal: item.kcal * factor,
                         protein: item.protein * factor, carbs: item.carbs * factor, fat: item.fat * factor,
                         nutrients: item.nutrients.scaled(by: factor), origin: .estimate)
    }

    /// The food after the user changed values of `original`. A product of Open Food Facts that is changed no longer claims to hold the
    /// values of that database: it becomes a typed food and keeps only a note about where it started, so third-party data and own
    /// values never share a record under the label of the third party. Without a change the food stays as it is.
    public func afterEditing(from original: FoodValue) -> FoodValue {
        guard original.origin == .openFoodFacts, origin == .openFoodFacts else { return self }
        var comparable = original
        comparable.name = name
        comparable.barcode = barcode
        guard comparable != self else { return self }
        var edited = self
        edited.origin = .typed
        edited.sourceNote = String(localized: "Ausgangswerte aus Open Food Facts, von dir geändert", bundle: .module)
        return edited
    }

    // MARK: Text

    /// "je 100 g · 62 kcal · 11 g Eiweiß": the line of a list row.
    public func summary(locale: Locale = .current) -> String {
        var parts = [reference.text(locale: locale), IntakeFormat.kcal(kcal, estimated: false, locale: locale)]
        if let protein {
            let value = IntakeFormat.grams(protein, estimated: false)
            parts.append(String(localized: "\(value) Eiweiß", bundle: .module))
        }
        return parts.joined(separator: " · ")
    }

    /// A number without trailing zeros, at most one decimal place: "250", "1,5".
    static func number(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Finds foods by words.
public enum FoodSearch {
    /// The foods whose name contains every word of `query`, ignoring case, accents and umlauts. An empty query returns all foods.
    /// The result is sorted by name, foods whose name starts with the first word first.
    public static func matching(_ foods: [FoodValue], query: String) -> [FoodValue] {
        let words = SearchText.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = foods.map { (food: $0, name: SearchText.fold($0.name)) }
        let hits = folded.filter { entry in words.allSatisfy { entry.name.contains($0) } }
        let sorted = hits.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let first = words.first else { return sorted.map(\.food) }
        return (sorted.filter { $0.name.hasPrefix(first) } + sorted.filter { !$0.name.hasPrefix(first) }).map(\.food)
    }
}
