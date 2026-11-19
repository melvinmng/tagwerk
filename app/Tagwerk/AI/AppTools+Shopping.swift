import Foundation
import TagwerkCore

/// The assistant's access to the shopping list (phase 5 design §5.8). Reading sends item names, quantities and
/// category names to ChatGPT, like task titles in the chat. Changing runs only after the user confirmed the card.
extension AppTools {
    static let maxListedShoppingItems = 100
    static let maxShoppingChanges = 30

    /// The shopping model with fresh data, or the error every shopping function answers without a usable list.
    private func readyShopping() async throws -> ShoppingModel {
        guard let shopping else { throw ToolError(Self.shoppingSetupError) }
        await shopping.reload()
        guard shopping.state == .ready else { throw ToolError(Self.shoppingSetupError) }
        return shopping
    }

    private static var shoppingSetupError: String {
        String(localized: "Es ist keine Einkaufsliste eingerichtet. Einstellungen › Einkaufsliste.")
    }

    func listShopping(includeCompleted: Bool) async throws -> String {
        let shopping = try await readyShopping()
        let open = shopping.openItems.prefix(Self.maxListedShoppingItems).map { item -> [String: Any] in
            ["id": item.id, "name": item.name, "quantity": item.quantity ?? NSNull(),
             "category": shopping.categoryName(of: item) ?? ShoppingSorter.otherName]
        }
        let completed = includeCompleted ? shopping.completedItems.map { ["id": $0.id, "name": $0.name] } : []
        return Self.json(["ok": true, "list": shopping.listTitle ?? "", "open": open, "completed": completed])
    }

    /// Adds items by the shopping model's rule (no duplicates, reopening) and checks items off. A reminder that
    /// does not lie in the shopping list is reported as not found and stays untouched. Partial failures do not
    /// stop the rest.
    func updateShopping(_ args: Arguments) async throws -> String {
        let additions = args.values["add"] as? [[String: Any]] ?? []
        let checkOff = args.strings("check_off")
        guard additions.count <= Self.maxShoppingChanges, checkOff.count <= Self.maxShoppingChanges else {
            throw ToolError(String(localized: "Höchstens 30 Artikel je Aufruf."))
        }
        let shopping = try await readyShopping()
        let items = additions.compactMap { entry -> ParsedItem? in
            let name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let quantity = (entry["quantity"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedItem(name: String(name.prefix(ShoppingInputParser.maxNameLength)),
                              quantity: quantity?.isEmpty == false ? quantity : nil)
        }
        let report = items.isEmpty ? ShoppingModel.AddReport() : await shopping.add(items)
        var checkedOff: [String] = []
        var notFound: [String] = []
        for id in checkOff {
            let name = shopping.openItems.first { $0.id == id }?.name
            do {
                try await shopping.checkOff(id: id)
                checkedOff.append(name ?? id)
            } catch {
                notFound.append(id)
            }
        }
        var result: [String: Any] = ["ok": true, "added": report.added, "reopened": report.reopened,
                                     "already_on_list": report.alreadyOnList, "checked_off": checkedOff, "not_found": notFound]
        if !report.failed.isEmpty {
            result["failed"] = report.failed
            result["failure"] = report.errorMessage ?? ""
        }
        return Self.json(result)
    }
}
