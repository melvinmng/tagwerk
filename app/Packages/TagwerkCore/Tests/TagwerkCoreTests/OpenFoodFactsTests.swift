import Foundation
import Testing
@testable import TagwerkCore

struct OpenFoodFactsTests {
    private let agent = "Tagwerk/9.9 (test@example.org)"

    // MARK: Requests

    @Test func searchRequest_carriesOnlyTheAgentAndTheAcceptHeader() throws {
        let request = OpenFoodFactsAPI.searchRequest(query: "  Skyr natur ", page: 1, userAgent: agent)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.allHTTPHeaderFields == ["User-Agent": agent, "Accept": "application/json"], "no cookie, token or identifier header")
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https" && components.host == "world.openfoodfacts.org" && components.path == "/cgi/search.pl")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["search_terms"] == "Skyr natur", "the typed words, trimmed")
        #expect(items["json"] == "1" && items["action"] == "process" && items["page"] == "1")
        #expect(items["page_size"] == String(OpenFoodFactsAPI.pageSize))
        #expect(items["fields"] == OpenFoodFactsAPI.fields, "only the fields the app uses")
        #expect(Set(items.keys) == ["search_terms", "search_simple", "action", "json", "page_size", "page", "fields"],
                "nothing about the user or the device is in the address")
    }

    @Test func searchRequest_encodesTheQuery() throws {
        let request = OpenFoodFactsAPI.searchRequest(query: "müsli & milch=1", page: 2, userAgent: agent)
        let url = try #require(request.url?.absoluteString)
        #expect(!url.contains("&%20"), "an ampersand typed by the user must not split the query")
        let components = try #require(URLComponents(string: url))
        #expect(components.queryItems?.first { $0.name == "search_terms" }?.value == "müsli & milch=1")
        #expect(components.queryItems?.first { $0.name == "page" }?.value == "2")
    }

    @Test func productRequest_onlyForRealBarcodes() throws {
        let request = try #require(OpenFoodFactsAPI.productRequest(barcode: " 4000000000000 ", userAgent: agent))
        #expect(request.url?.path == "/api/v2/product/4000000000000")
        #expect(request.allHTTPHeaderFields == ["User-Agent": agent, "Accept": "application/json"])
        for bad in ["", "123", "abc12345678", "4000000000000/../x", "40000000000001234567", "4000 0000 0000"] {
            #expect(OpenFoodFactsAPI.productRequest(barcode: bad, userAgent: agent) == nil, "\(bad) is not a barcode")
        }
    }

    // MARK: Mapping

    private func product(_ nutriments: [String: Any], name: String? = "Skyr natur", code: String? = "4000000000000", quantity: String? = "450 g",
                         serving: String? = nil, servingQuantity: Any? = nil, brands: String? = "Milbona, Lidl") -> [String: Any] {
        var result: [String: Any] = ["nutriments": nutriments]
        if let name { result["product_name"] = name }
        if let code { result["code"] = code }
        if let quantity { result["quantity"] = quantity }
        if let serving { result["serving_size"] = serving }
        if let servingQuantity { result["serving_quantity"] = servingQuantity }
        if let brands { result["brands"] = brands }
        return result
    }

    private func candidate(_ nutriments: [String: Any], quantity: String? = "450 g", serving: String? = nil, servingQuantity: Any? = nil) throws -> ProductCandidate {
        try #require(OpenFoodFactsAPI.candidate(from: product(nutriments, quantity: quantity, serving: serving, servingQuantity: servingQuantity)))
    }

    @Test func map_missingFieldsStayUnknown() throws {
        let result = try candidate(["energy-kcal_100g": 62, "proteins_100g": 11])
        #expect(result.food.kcal == 62 && result.food.protein == 11)
        #expect(result.food.carbs == nil && result.food.fat == nil, "a missing value is not 0")
        #expect(result.food.nutrients == NutrientValues())
        #expect(result.isIncomplete && !result.energyUnknown)
        #expect(result.food.origin == .openFoodFacts)
    }

    @Test func map_complete() throws {
        let result = try candidate(["energy-kcal_100g": 62, "proteins_100g": 11, "carbohydrates_100g": 4, "fat_100g": 0.2, "fiber_100g": 0,
                                    "sugars_100g": 4, "saturated-fat_100g": 0.1, "salt_100g": 0.1])
        #expect(!result.isIncomplete)
        #expect(result.food.nutrients == NutrientValues(fiber: 0, sugar: 4, saturatedFat: 0.1, salt: 0.1), "a stated 0 stays 0")
        #expect(result.food.reference == .per100g && !result.valuesPerServingOnly)
    }

    @Test func map_kJOnly_convertsToKcal() throws {
        let fromKJ = try candidate(["energy-kj_100g": 1046])
        #expect(abs(fromKJ.food.kcal - 250) < 0.01 && !fromKJ.energyUnknown)
        let generic = try candidate(["energy_100g": 418.4])
        #expect(abs(generic.food.kcal - 100) < 0.01, "the generic energy key is kilojoules")
        let both = try candidate(["energy-kcal_100g": 240, "energy-kj_100g": 1046])
        #expect(both.food.kcal == 240, "kilocalories win")
    }

    @Test func map_noEnergy_isMarkedUnknown() throws {
        let result = try candidate(["proteins_100g": 11])
        #expect(result.energyUnknown && result.isIncomplete)
    }

    @Test func map_saltOrSodium() throws {
        #expect(try candidate(["salt_100g": 1.25, "sodium_100g": 0.1]).food.nutrients.salt == 1.25, "salt wins")
        let fromSodium = try candidate(["sodium_100g": 0.4])
        #expect(fromSodium.food.nutrients.salt == 1.0, "sodium × 2.5")
        #expect(try candidate(["proteins_100g": 1]).food.nutrients.salt == nil)
    }

    @Test func map_perServingOnly_marksReference() throws {
        let result = try candidate(["energy-kcal_serving": 168, "proteins_serving": 15], quantity: "45 g", servingQuantity: "45")
        #expect(result.valuesPerServingOnly)
        #expect(result.food.reference == .perPiece(grams: 45))
        #expect(result.food.kcal == 168 && result.food.protein == 15)
    }

    @Test func map_per100gWinsOverServing() throws {
        let result = try candidate(["energy-kcal_100g": 62, "energy-kcal_serving": 280, "proteins_serving": 50])
        #expect(!result.valuesPerServingOnly && result.food.kcal == 62)
        #expect(result.food.protein == nil, "serving values are never mixed into 100 g values")
    }

    @Test func map_drinksAreMillilitres() throws {
        #expect(try candidate(["energy-kcal_100g": 47], quantity: "1 l").food.reference == .per100ml)
        #expect(try candidate(["energy-kcal_100g": 47], quantity: "330 ml").food.reference == .per100ml)
        #expect(try candidate(["energy-kcal_100g": 47], quantity: "6 x 33 cl").food.reference == .per100ml)
        #expect(try candidate(["energy-kcal_100g": 47], quantity: "450 g").food.reference == .per100g)
        #expect(try candidate(["energy-kcal_100g": 47], quantity: nil).food.reference == .per100g)
    }

    @Test func map_numbersAsStrings() throws {
        let result = try candidate(["energy-kcal_100g": "62,5", "proteins_100g": "11.2", "fat_100g": ""])
        #expect(result.food.kcal == 62.5 && result.food.protein == 11.2 && result.food.fat == nil)
    }

    @Test func map_absurdValuesAreDropped() throws {
        let result = try candidate(["energy-kcal_100g": 4500, "proteins_100g": -2, "fat_100g": 130])
        #expect(result.energyUnknown && result.food.protein == nil && result.food.fat == nil)
    }

    @Test func map_namesBrandAndBarcode() throws {
        let result = try candidate(["energy-kcal_100g": 62])
        #expect(result.name == "Skyr natur" && result.brand == "Milbona" && result.quantity == "450 g")
        #expect(result.barcode == "4000000000000" && result.id == "4000000000000")
        let german = try #require(OpenFoodFactsAPI.candidate(from: ["product_name_de": "Quark", "product_name": "Curd", "nutriments": [String: Any]()]))
        #expect(german.name == "Quark", "the German name is preferred")
        #expect(OpenFoodFactsAPI.candidate(from: ["nutriments": ["energy-kcal_100g": 10]]) == nil, "a product without a name is not listed")
        #expect(OpenFoodFactsAPI.candidate(from: ["product_name": "  ", "nutriments": [String: Any]()]) == nil)
    }

    @Test func map_aProductWithoutValuesIsStillListed() throws {
        let result = try candidate([:])
        #expect(result.energyUnknown && result.isIncomplete && result.food.protein == nil)
    }

    // MARK: Answers

    @Test func readSearch_pageAndMore() throws {
        let json = #"{"count":"45","page":1,"page_size":20,"products":[{"code":"1","product_name":"A","nutriments":{}},{"code":"2","nutriments":{}},{"code":"3","product_name":"C","nutriments":{"energy-kcal_100g":5}}]}"#
        let page = try OpenFoodFactsAPI.readSearch(Data(json.utf8), page: 1)
        #expect(page.candidates.map(\.name) == ["A", "C"], "a hit without a name is left out")
        #expect(page.total == 45 && page.page == 1 && page.hasMore)
        let last = try OpenFoodFactsAPI.readSearch(Data(#"{"count":20,"page":1,"page_size":20,"products":[]}"#.utf8), page: 1)
        #expect(!last.hasMore && last.candidates.isEmpty)
    }

    @Test func readSearch_notJSON_throws() {
        #expect(throws: OpenFoodFactsAPI.ReadError.notJSON) { try OpenFoodFactsAPI.readSearch(Data("<html>".utf8), page: 1) }
    }

    @Test func readProduct_foundAndNotFound() throws {
        let found = Data(#"{"code":"4000000000000","status":1,"product":{"product_name":"Skyr","nutriments":{"energy-kcal_100g":62}}}"#.utf8)
        let product = try #require(try OpenFoodFactsAPI.readProduct(found))
        #expect(product.barcode == "4000000000000" && product.food.kcal == 62)
        let missing = Data(#"{"code":"4000000000000","status":0,"status_verbose":"product not found"}"#.utf8)
        #expect(try OpenFoodFactsAPI.readProduct(missing) == nil)
    }

    // MARK: Taking a product over

    @Test func food_takenOverKeepsSourceAndBarcode_withANewIdentity() throws {
        let result = try candidate(["energy-kcal_100g": 62, "proteins_100g": 11])
        let date = Date(timeIntervalSince1970: 1_795_262_400)   // 2026-11-21 12:00 UTC
        let food = result.food(retrievedOn: date, locale: Locale(identifier: "de_DE"))
        #expect(food.origin == .openFoodFacts && food.barcode == "4000000000000")
        #expect(food.sourceNote?.contains("Open Food Facts") == true)
        #expect(food.sourceNote?.contains("2026") == true)
        #expect(food.id != result.food.id)
        #expect(result.food(retrievedOn: date).id != food.id, "taking it over twice gives two entries")
    }
}
