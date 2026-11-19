import Foundation

/// The ten categories Tagwerk creates once. The order is their default order in the list.
public enum ShoppingBuiltinCategory: String, Sendable, CaseIterable {
    case produce, bakery, chilled, meat, frozen, pantry, snacks, drinks, household, care

    /// Name in the current app language. It is copied into the stored category when that is created
    /// and is user data from then on.
    public var localizedName: String {
        switch self {
        case .produce: String(localized: "Obst & Gemüse", bundle: .module)
        case .bakery: String(localized: "Brot & Backwaren", bundle: .module)
        case .chilled: String(localized: "Kühlregal", bundle: .module)
        case .meat: String(localized: "Fleisch & Fisch", bundle: .module)
        case .frozen: String(localized: "Tiefkühl", bundle: .module)
        case .pantry: String(localized: "Vorrat & Konserven", bundle: .module)
        case .snacks: String(localized: "Frühstück & Süßes", bundle: .module)
        case .drinks: String(localized: "Getränke", bundle: .module)
        case .household: String(localized: "Haushalt", bundle: .module)
        case .care: String(localized: "Drogerie", bundle: .module)
        }
    }

    /// Name of the fixed last section for everything without a category.
    public static var otherName: String { String(localized: "Sonstiges", bundle: .module) }
}

/// Plain copy of a stored category.
public struct ShoppingCategoryInfo: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var sortIndex: Int
    /// Raw value of `ShoppingBuiltinCategory` for built-in categories; `nil` for the user's own.
    public var builtinKey: String?

    public init(id: UUID, name: String, sortIndex: Int, builtinKey: String?) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.builtinKey = builtinKey
    }
}

/// Bundled word list that maps item names to built-in categories, offline and independent of the app language.
public struct ShoppingDictionary: Sendable {
    /// Shortest term that may match as the ending of a longer name ("Hafermilch" ends with "milch").
    static let minimumSuffixLength = 4

    private let builtinKeyByTerm: [String: String]
    /// Terms long enough for an ending match, longest first.
    private let suffixTerms: [String]

    /// `entries` maps a built-in key to its terms; the terms are name keys (`ShoppingName.key`).
    public init(entries: [String: [String]]) {
        var index: [String: String] = [:]
        for (builtinKey, terms) in entries.sorted(by: { $0.key < $1.key }) {
            for term in terms where index[term] == nil { index[term] = builtinKey }
        }
        builtinKeyByTerm = index
        suffixTerms = index.keys.filter { $0.count >= Self.minimumSuffixLength }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    }

    public static let bundled = ShoppingDictionary(entries: bundledEntries)

    /// Content of `ShoppingDictionary.json`; empty when the resource is missing or damaged.
    static var bundledEntries: [String: [String]] {
        guard let url = Bundle.module.url(forResource: "ShoppingDictionary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return entries
    }

    /// The longest match wins: (a) the whole key, (b) one word of the key, (c) the key ends with a term of
    /// at least four characters. Equal lengths are decided in that order.
    public func builtinKey(forKey key: String) -> String? {
        var best: (length: Int, builtinKey: String)?
        func offer(_ term: String) {
            guard let builtinKey = builtinKeyByTerm[term], term.count > (best?.length ?? 0) else { return }
            best = (term.count, builtinKey)
        }
        offer(key)
        for word in key.split(separator: " ") { offer(String(word)) }
        if let suffix = suffixTerms.first(where: { key.hasSuffix($0) }) { offer(suffix) }
        return best?.builtinKey
    }
}

/// Plain copy of a learned assignment "item name → category".
public struct ShoppingAssignmentInfo: Sendable, Hashable {
    /// `nil` places the name under "Sonstiges" on purpose.
    public var categoryID: UUID?
    /// Chosen by the user; suggestions from ChatGPT never replace such an assignment.
    public var isManual: Bool

    public init(categoryID: UUID?, isManual: Bool) {
        self.categoryID = categoryID
        self.isManual = isManual
    }
}

public enum ShoppingClassifier {
    /// Category of a name key, or `nil` for "Sonstiges". First match: a learned assignment whose category still
    /// exists (an assignment without category means "Sonstiges"), then the dictionary if a category with its
    /// built-in key exists.
    public static func categoryID(forKey key: String, assignments: [String: ShoppingAssignmentInfo],
                                  categories: [ShoppingCategoryInfo], dictionary: ShoppingDictionary) -> UUID? {
        if let assignment = assignments[key] {
            guard let categoryID = assignment.categoryID else { return nil }
            if categories.contains(where: { $0.id == categoryID }) { return categoryID }
        }
        guard let builtinKey = dictionary.builtinKey(forKey: key) else { return nil }
        return categories.first { $0.builtinKey == builtinKey }?.id
    }
}

/// One section of the shopping list.
public struct ShoppingSection: Sendable, Hashable, Identifiable {
    /// `nil` is the fixed section "Sonstiges".
    public var categoryID: UUID?
    public var items: [ShoppingItem]

    public init(categoryID: UUID?, items: [ShoppingItem]) {
        self.categoryID = categoryID
        self.items = items
    }

    public var id: String { categoryID?.uuidString ?? "other" }
}

public enum ShoppingSections {
    /// Sections by `sortIndex`, "Sonstiges" last, empty sections left out. Inside a section by creation date
    /// ascending; equal or missing dates by title, items without a date after dated ones.
    public static func make(open items: [ShoppingItem], assignments: [String: ShoppingAssignmentInfo],
                            categories: [ShoppingCategoryInfo], dictionary: ShoppingDictionary) -> [ShoppingSection] {
        var itemsByCategory: [UUID?: [ShoppingItem]] = [:]
        for item in items {
            let categoryID = ShoppingClassifier.categoryID(forKey: ShoppingName.key(item.name), assignments: assignments,
                                                           categories: categories, dictionary: dictionary)
            itemsByCategory[categoryID, default: []].append(item)
        }
        let ordered = categories.sorted { $0.sortIndex != $1.sortIndex ? $0.sortIndex < $1.sortIndex : $0.name < $1.name }
        let order: [UUID?] = ordered.map(\.id) + [nil]
        return order.compactMap { categoryID in
            guard let sectionItems = itemsByCategory[categoryID], !sectionItems.isEmpty else { return nil }
            return ShoppingSection(categoryID: categoryID, items: sectionItems.sorted(by: precedes))
        }
    }

    private static func precedes(_ first: ShoppingItem, _ second: ShoppingItem) -> Bool {
        switch (first.createdAt, second.createdAt) {
        case let (a?, b?) where a != b: return a < b
        case (.some, nil): return true
        case (nil, .some): return false
        default:
            let order = first.name.localizedStandardCompare(second.name)
            return order != .orderedSame ? order == .orderedAscending : first.id < second.id
        }
    }
}

public enum ShoppingCategoryRules {
    public static let maxCategories = 30
    public static let maxNameLength = 30
    /// Names of the fixed section in both languages; no category may take them, whatever the app language is.
    static let reservedNames: Set<String> = ["sonstiges", "other"]

    public enum NameError: Error, Equatable, Sendable {
        case empty, tooLong, duplicate, reserved, limitReached
    }

    /// Returns the trimmed name. `existing` are the other categories' names (the renamed one excluded).
    public static func validatedName(_ raw: String, existing: [String], isNew: Bool) throws(NameError) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw .empty }
        if name.count > maxNameLength { throw .tooLong }
        let lowered = name.lowercased()
        if reservedNames.contains(lowered) { throw .reserved }
        if existing.contains(where: { $0.lowercased() == lowered }) { throw .duplicate }
        if isNew && existing.count >= maxCategories { throw .limitReached }
        return name
    }
}
