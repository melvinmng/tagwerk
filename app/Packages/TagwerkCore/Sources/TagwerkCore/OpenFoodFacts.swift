import Foundation

/// A product of Open Food Facts as the app shows it: what is needed to list it, to preview it and to take it over as a food.
///
/// The data come from volunteers and can be missing or wrong. Search hits live in memory only; nothing of this type is stored.
/// Taking a product over creates a separate `FoodValue` (see `food(retrievedOn:)`).
public struct ProductCandidate: Sendable, Hashable, Identifiable {
    public var barcode: String?
    public var name: String
    public var brand: String?
    /// The package size as printed ("500 g").
    public var quantity: String?
    /// The values as a food. Origin is `openFoodFacts`; the source note is added when the user takes the product over.
    public var food: FoodValue
    /// The product gives no usable energy value.
    public var energyUnknown: Bool
    /// The values are those of one serving, not of 100 g or 100 ml (the product states nothing else).
    public var valuesPerServingOnly: Bool

    public var id: String { barcode ?? food.id.uuidString }

    public init(barcode: String?, name: String, brand: String?, quantity: String?, food: FoodValue, energyUnknown: Bool,
                valuesPerServingOnly: Bool) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.food = food
        self.energyUnknown = energyUnknown
        self.valuesPerServingOnly = valuesPerServingOnly
    }

    /// Energy or one of the macronutrients is missing ("Angaben unvollständig"): the label photo is offered as a way to fill the gaps.
    public var isIncomplete: Bool { energyUnknown || food.protein == nil || food.carbs == nil || food.fat == nil }

    /// The food to take over, with the source and the day of retrieval in its note. A copy with a new identity, so a product that is
    /// taken over twice gives two entries and never changes an earlier one.
    public func food(retrievedOn date: Date, locale: Locale = .current) -> FoodValue {
        var result = food
        result.id = UUID()
        result.barcode = barcode
        let day = date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
        result.sourceNote = String(localized: "Open Food Facts, abgerufen am \(day)", bundle: .module)
        return result
    }
}

/// One page of search results.
public struct ProductPage: Sendable, Hashable {
    public var candidates: [ProductCandidate]
    public var page: Int
    /// All hits of the search, when the answer says.
    public var total: Int?
    /// More hits follow on the next page.
    public var hasMore: Bool

    public init(candidates: [ProductCandidate], page: Int, total: Int?, hasMore: Bool) {
        self.candidates = candidates
        self.page = page
        self.total = total
        self.hasMore = hasMore
    }
}

/// The requests to Open Food Facts and the reading of their answers. No network here: the app sends the requests.
public enum OpenFoodFactsAPI {
    /// The legacy search; the full-text search of the newer service has no terms of use that were found (research 21.11.2026).
    public static let searchURL = URL(string: "https://world.openfoodfacts.org/cgi/search.pl")!
    public static let productURL = URL(string: "https://world.openfoodfacts.org/api/v2/product")!
    /// Hits per page; one page is all a search shows. More hits are a tap of their own and count against the limit.
    public static let pageSize = 20
    /// The fields the app needs; the operator asks clients to request only what they use.
    public static let fields = "code,product_name,product_name_de,product_name_en,brands,quantity,serving_size,serving_quantity,nutriments"
    public static let timeout: TimeInterval = 15

    /// The search request for `query` (page 1 is the first). Carries the user agent and nothing else about the user: no cookies, no
    /// account, no identifier.
    public static func searchRequest(query: String, page: Int, userAgent: String) -> URLRequest {
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "fields", value: fields),
        ]
        return request(components.url!, userAgent: userAgent)
    }

    /// The request for one product by its barcode; `nil` for something that is not a barcode (8 to 14 digits).
    public static func productRequest(barcode: String, userAgent: String) -> URLRequest? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...14).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var components = URLComponents(url: productURL.appendingPathComponent(code), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return request(components.url!, userAgent: userAgent)
    }

    private static func request(_ url: URL, userAgent: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        return request
    }

    // MARK: Reading answers

    public enum ReadError: Error, Equatable { case notJSON }

    /// The page of a search answer. A hit without a name is left out (it could not be listed).
    public static func readSearch(_ data: Data, page requestedPage: Int) throws -> ProductPage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.notJSON }
        let products = (root["products"] as? [[String: Any]] ?? []).compactMap(candidate(from:))
        let page = integer(root["page"]) ?? requestedPage
        let total = integer(root["count"])
        let size = integer(root["page_size"]) ?? pageSize
        let hasMore = total.map { page * size < $0 } ?? false
        return ProductPage(candidates: products, page: page, total: total, hasMore: hasMore)
    }

    /// The product of a lookup by barcode; `nil` when the database does not know it.
    public static func readProduct(_ data: Data) throws -> ProductCandidate? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.notJSON }
        guard integer(root["status"]) != 0, let product = root["product"] as? [String: Any] else { return nil }
        var withCode = product
        if withCode["code"] == nil { withCode["code"] = root["code"] }
        return candidate(from: withCode)
    }

    // MARK: Mapping

    /// Kilojoules per kilocalorie.
    private static let kilojoulesPerKilocalorie = 4.184
    private static let maximumKcalPer100 = 1000.0
    private static let maximumKcalPerServing = 5000.0

    /// One product as a candidate; `nil` without a name. Missing values stay unknown, never 0.
    static func candidate(from product: [String: Any]) -> ProductCandidate? {
        let name = firstText(product["product_name_de"], product["product_name"], product["product_name_en"])
        guard let name else { return nil }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let quantity = text(product["quantity"])
        let servingSize = text(product["serving_size"])
        let brand = text(product["brands"]).flatMap { $0.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } }
            .flatMap { $0.isEmpty ? nil : $0 }

        let has100 = hasAnyValue(nutriments, suffix: "_100g")
        let hasServing = hasAnyValue(nutriments, suffix: "_serving")
        let perServing = !has100 && hasServing
        let suffix = perServing ? "_serving" : "_100g"
        let reference: FoodReference
        if perServing {
            let grams = number(product["serving_quantity"]).flatMap { $0 > 0 && $0 <= 5000 ? $0 : nil }
            reference = .perPiece(grams: grams)
        } else {
            reference = looksLiquid(quantity: quantity, servingSize: servingSize) ? .per100ml : .per100g
        }

        let values = read(nutriments, suffix: suffix, servingBasis: perServing)
        let food = FoodValue(name: name, reference: reference, kcal: values.kcal ?? 0, protein: values.protein, carbs: values.carbs,
                             fat: values.fat, nutrients: values.nutrients, origin: .openFoodFacts, barcode: text(product["code"]))
        return ProductCandidate(barcode: text(product["code"]), name: name, brand: brand, quantity: quantity, food: food,
                                energyUnknown: values.kcal == nil, valuesPerServingOnly: perServing)
    }

    private struct Values {
        var kcal: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var nutrients = NutrientValues()
    }

    private static func read(_ nutriments: [String: Any], suffix: String, servingBasis: Bool) -> Values {
        let energyLimit = servingBasis ? maximumKcalPerServing : maximumKcalPer100
        let gramLimit = servingBasis ? 5000.0 : 100.0
        func value(_ key: String, maximum: Double) -> Double? {
            guard let number = number(nutriments[key + suffix]), number >= 0, number <= maximum else { return nil }
            return number
        }
        var result = Values()
        // Energy: kilocalories when given, otherwise kilojoules (`energy-kj`, or the generic `energy`, which is kilojoules).
        result.kcal = value("energy-kcal", maximum: energyLimit)
            ?? (value("energy-kj", maximum: energyLimit * kilojoulesPerKilocalorie) ?? value("energy", maximum: energyLimit * kilojoulesPerKilocalorie))
                .map { $0 / kilojoulesPerKilocalorie }
        result.protein = value("proteins", maximum: gramLimit)
        result.carbs = value("carbohydrates", maximum: gramLimit)
        result.fat = value("fat", maximum: gramLimit)
        result.nutrients.fiber = value("fiber", maximum: gramLimit)
        result.nutrients.sugar = value("sugars", maximum: gramLimit)
        result.nutrients.saturatedFat = value("saturated-fat", maximum: gramLimit)
        // Salt, otherwise sodium (grams) as salt.
        result.nutrients.salt = value("salt", maximum: gramLimit)
            ?? value("sodium", maximum: gramLimit).map { NutrientValues.salt(fromSodiumGrams: $0) }
        return result
    }

    private static let valueKeys = ["energy-kcal", "energy-kj", "energy", "proteins", "carbohydrates", "fat", "fiber", "sugars",
                                    "saturated-fat", "salt", "sodium"]

    private static func hasAnyValue(_ nutriments: [String: Any], suffix: String) -> Bool {
        valueKeys.contains { number(nutriments[$0 + suffix]) != nil }
    }

    /// Drinks list their values per 100 ml. The data does not say so directly; the package size does ("330 ml", "1 l").
    static func looksLiquid(quantity: String?, servingSize: String?) -> Bool {
        let text = [quantity, servingSize].compactMap { $0 }.joined(separator: " ").lowercased()
        let pattern = #"\d\s*(ml|cl|dl|l)\b"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return false }
        return text.range(of: #"\d\s*(g|kg)\b"#, options: .regularExpression) == nil
    }

    // MARK: Values of loose JSON

    /// The API returns numbers as numbers or as strings.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): return number.doubleValue
        case let text as String: return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    private static func integer(_ value: Any?) -> Int? { number(value).map { Int($0) } }

    private static func text(_ value: Any?) -> String? {
        let result: String?
        switch value {
        case let text as String: result = text
        case let number as NSNumber: result = number.stringValue
        default: result = nil
        }
        guard let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func firstText(_ values: Any?...) -> String? { values.lazy.compactMap { text($0) }.first }
}
