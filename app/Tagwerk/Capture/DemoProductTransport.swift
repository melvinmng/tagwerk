#if DEBUG && targetEnvironment(simulator)
import Foundation
import GitHubKit

/// Scripted answers of Open Food Facts for the UI tests and for checking the screens in the simulator without a network, enabled with
/// the launch argument `-TagwerkDemoFoodLookup`. The addresses and values are invented.
struct DemoProductTransport: HTTPTransport {
    static let launchArgument = "-TagwerkDemoFoodLookup"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    static let searchBody = """
    {"count":2,"page":1,"page_size":20,"products":[\
    {"code":"4000000000001","product_name":"Demo Skyr natur","brands":"Demomolkerei","quantity":"450 g","nutriments":{"energy-kj_100g":260,"proteins_100g":11.37,"carbohydrates_100g":4,"fat_100g":0.2,"sugars_100g":4,"salt_100g":0.15}},\
    {"code":"4000000000002","product_name":"Demo Skyr Vanille","brands":"Demomolkerei","quantity":"150 g","nutriments":{"proteins_100g":9}}]}
    """

    /// The barcodes the scan answers (valid check digits): a complete product, a product without energy, and the "unknown" answer for
    /// every other code.
    static let knownBarcode = "4000000000006"
    static let incompleteBarcode = "4000000000013"

    static func productBody(forBarcode code: String) -> String {
        switch code {
        case knownBarcode:
            """
            {"status":1,"code":"\(code)","product":{"code":"\(code)","product_name":"Demo Skyr natur","brands":"Demomolkerei","quantity":"450 g",\
            "nutriments":{"energy-kj_100g":260,"proteins_100g":11.37,"carbohydrates_100g":4,"fat_100g":0.2,"sugars_100g":4,"salt_100g":0.15}}}
            """
        case incompleteBarcode:
            #"{"status":1,"code":"\#\(code)","product":{"code":"\#\(code)","product_name":"Demo Skyr Vanille","brands":"Demomolkerei","quantity":"150 g","nutriments":{"proteins_100g":9}}}"#
        default:
            #"{"status":0}"#
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let body: String
        if path.hasPrefix("/api/v2/product") {
            body = Self.productBody(forBarcode: request.url?.lastPathComponent ?? "")
        } else {
            body = Self.searchBody
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
