import Foundation

/// One use of an item name on the shopping list: an open item or a completed one.
public struct ShoppingHistoryEntry: Sendable, Hashable {
    public var name: String
    /// When the item was created or completed, whichever is later; `nil` if the store reports neither.
    public var date: Date?

    public init(name: String, date: Date?) {
        self.name = name
        self.date = date
    }
}

/// The article names offered to Siri for "Füge … zur Einkaufsliste hinzu": the names the user has used before,
/// then common terms from the offline dictionary. Siri can only recognize names it was given in advance.
public enum ShoppingSuggestions {
    /// Upper limit of offered names. Each name is expanded into every phrase that uses it, and the system
    /// caps the total number of phrases, so the list stays small.
    public static let defaultLimit = 150

    /// Own names first (most frequent first, then most recent, then by name), then the common terms in their
    /// given order. Names that differ only in case, diacritics or surrounding blanks count once; of the own
    /// spellings the newest one is shown.
    public static func articles(history: [ShoppingHistoryEntry], commonTerms: [String], limit: Int = defaultLimit) -> [String] {
        guard limit > 0 else { return [] }
        struct Usage { var count = 0; var latest: Date?; var spelling = ""; var spellingDate: Date? }
        var usageByKey: [String: Usage] = [:]
        for entry in history {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ShoppingName.key(name)
            guard !key.isEmpty else { continue }
            var usage = usageByKey[key] ?? Usage(spelling: name, spellingDate: entry.date)
            usage.count += 1
            if let date = entry.date {
                if usage.latest.map({ date > $0 }) ?? true { usage.latest = date }
                if usage.spellingDate.map({ date > $0 }) ?? true { usage.spelling = name; usage.spellingDate = date }
            }
            usageByKey[key] = usage
        }
        let ownKeys = usageByKey.keys.sorted { lhs, rhs in
            let (a, b) = (usageByKey[lhs]!, usageByKey[rhs]!)
            if a.count != b.count { return a.count > b.count }
            if a.latest != b.latest { return (a.latest ?? .distantPast) > (b.latest ?? .distantPast) }
            return lhs < rhs
        }
        var seen = Set<String>()
        var result: [String] = []
        for key in ownKeys {
            seen.insert(key)
            result.append(usageByKey[key]!.spelling)
        }
        for term in commonTerms {
            let name = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ShoppingName.key(name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return Array(result.prefix(limit))
    }

    /// The names that contain the typed or spoken text, ignoring case and diacritics; names that start with it
    /// come first, the given order is kept inside each group.
    public static func matching(_ query: String, in names: [String]) -> [String] {
        let queryKey = ShoppingName.key(query)
        guard !queryKey.isEmpty else { return [] }
        let candidates = names.map { (name: $0, key: ShoppingName.key($0)) }.filter { $0.key.contains(queryKey) }
        return candidates.filter { $0.key.hasPrefix(queryKey) }.map(\.name)
            + candidates.filter { !$0.key.hasPrefix(queryKey) }.map(\.name)
    }

    /// Common items with their proper spelling, most common first; every one is a term of the offline dictionary
    /// (a test checks that). The list of the given language comes first, the other one follows.
    public static func commonTerms(preferEnglish: Bool) -> [String] {
        let combined = preferEnglish ? english + german : german + english
        var seen = Set<String>()
        return combined.filter { seen.insert(ShoppingName.key($0)).inserted }
    }

    private static let german = [
        "Milch", "Brot", "Eier", "Butter", "Käse", "Joghurt", "Kaffee", "Wasser", "Nudeln", "Reis", "Kartoffeln",
        "Zwiebeln", "Tomaten", "Äpfel", "Bananen", "Gurke", "Paprika", "Karotten", "Salat", "Knoblauch", "Zitronen",
        "Orangen", "Mehl", "Zucker", "Salz", "Pfeffer", "Öl", "Olivenöl", "Sahne", "Quark", "Schinken", "Wurst",
        "Hähnchen", "Hackfleisch", "Lachs", "Brötchen", "Toilettenpapier", "Küchenrolle", "Spülmittel", "Waschmittel",
        "Zahnpasta", "Duschgel", "Shampoo", "Seife", "Müllbeutel", "Taschentücher", "Tee", "Saft", "Bier", "Wein",
        "Mineralwasser", "Cola", "Schokolade", "Kekse", "Chips", "Müsli", "Haferflocken", "Marmelade", "Honig",
        "Tomatenmark", "Passierte Tomaten", "Thunfisch", "Linsen", "Kichererbsen", "Spaghetti", "Pizza", "Pommes",
        "Eis", "Erbsen", "Spinat", "Brokkoli", "Zucchini", "Champignons", "Erdbeeren", "Mozzarella", "Parmesan",
        "Schmand", "Frischkäse", "Hafermilch", "Tofu", "Margarine",
    ]

    private static let english = [
        "Milk", "Bread", "Eggs", "Butter", "Cheese", "Yogurt", "Coffee", "Water", "Pasta", "Rice", "Potatoes",
        "Onions", "Tomatoes", "Apples", "Bananas", "Cucumber", "Carrots", "Lettuce", "Garlic", "Lemons", "Flour",
        "Sugar", "Salt", "Olive oil", "Cream", "Ham", "Chicken", "Salmon", "Toilet paper", "Paper towels",
        "Dish soap", "Laundry detergent", "Toothpaste", "Shampoo", "Soap", "Tea", "Juice", "Beer", "Wine",
        "Chocolate", "Cookies", "Chips", "Cereal", "Honey", "Peanut butter", "Tuna", "Oat milk",
    ]
}
