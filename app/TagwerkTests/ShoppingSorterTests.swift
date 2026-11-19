import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A responder that answers after a delay, for the timeout.
private final class SlowResponder: ResponseStreaming, @unchecked Sendable {
    let answer: String
    let delay: Duration
    init(answer: String, delay: Duration) { self.answer = answer; self.delay = delay }
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: self.delay)
                continuation.yield(.textDelta(self.answer))
                continuation.yield(.completed(usage: nil))
                continuation.finish()
            }
        }
    }
}

@MainActor
struct ShoppingSorterTests {
    let responder = FakePlanResponder()
    final class Counter { var value = 0 }
    let modelCalls = Counter()
    let request = ShoppingSorter.Request(itemNames: ["Milch", "Sojasauce", "Reis", "Katzenstreu"],
                                         categoryNames: ["Kühlregal", "Vorrat & Konserven", "Getränke", "Sonstiges"])
    let current = ["milch": "Kühlregal", "reis": "Vorrat & Konserven"]

    private func sorter(_ responder: (any ResponseStreaming)? = nil, consent: Bool = true,
                        timeout: Duration = .seconds(30)) -> ShoppingSorter {
        let calls = modelCalls
        return ShoppingSorter(responder: responder ?? self.responder, model: { calls.value += 1; return "gpt-test" },
                              hasConsent: { consent }, timeout: timeout)
    }

    private func answer(_ assignments: [(String, String)], new: [String] = []) -> Data {
        let object: [String: Any] = ["assignments": assignments.map { ["item": $0.0, "category": $0.1] }, "new_categories": new]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func validate(_ assignments: [(String, String)], new: [String] = []) throws -> ShoppingSorter.Proposal {
        try ShoppingSorter.validate(answer(assignments, new: new), request: request, current: current)
    }

    // MARK: Request

    @Test func sort_withoutConsent_sendsNothing() async {
        await #expect(throws: ShoppingSorter.Failure.consentMissing) {
            try await sorter(consent: false).sort(request, current: [:])
        }
        #expect(responder.calls.isEmpty && modelCalls.value == 0)
    }

    @Test func request_skipsManualAssignments_capsAtSixty_sendsNoQuantities() {
        let items = (1...70).map { ShoppingItem(id: "\($0)", name: "Artikel \($0)", quantity: "2 Packungen") }
        let manual = Dictionary(uniqueKeysWithValues: (1...5).map {
            (ShoppingName.key("Artikel \($0)"), ShoppingAssignmentInfo(categoryID: nil, isManual: true))
        })
        let suggested = [ShoppingName.key("Artikel 6"): ShoppingAssignmentInfo(categoryID: nil, isManual: false)]
        let categories = [ShoppingCategoryInfo(id: UUID(), name: "Getränke", sortIndex: 1, builtinKey: "drinks"),
                          ShoppingCategoryInfo(id: UUID(), name: "Kühlregal", sortIndex: 0, builtinKey: "chilled")]
        let request = ShoppingSorter.request(sections: [ShoppingSection(categoryID: nil, items: items)],
                                             assignments: manual.merging(suggested) { first, _ in first }, categories: categories)
        #expect(request.itemNames.count == 60)
        #expect(request.itemNames.first == "Artikel 6")
        #expect(!request.itemNames.contains("Artikel 5"))
        #expect(request.itemNames.allSatisfy { !$0.contains("Packungen") })
        #expect(request.categoryNames == ["Kühlregal", "Getränke", "Sonstiges"])
    }

    @Test func sort_sendsOnlyNamesAndCategories_withSchema() async throws {
        responder.enqueue(String(decoding: answer([("Sojasauce", "Vorrat & Konserven")]), as: UTF8.self))
        let proposal = try await sorter().sort(request, current: current)
        #expect(proposal.changes == [.init(itemName: "Sojasauce", fromCategory: "Sonstiges", toCategory: "Vorrat & Konserven")])
        let call = try #require(responder.calls.first)
        #expect(call.schema == "shopping_sort")
        guard case .user(let text)? = call.input.first else { Issue.record("expected one user item"); return }
        let sent = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [String]])
        #expect(sent == ["items": request.itemNames, "categories": request.categoryNames])
    }

    // MARK: Validation

    @Test func validate_dropsUnknownItemsAndUnknownCategories() throws {
        let proposal = try validate([("Pizza", "Kühlregal"), ("Reis", "Erfunden")])
        #expect(proposal == ShoppingSorter.Proposal(newCategories: [], changes: []))
    }

    @Test func validate_keepsOnlyChanges() throws {
        let proposal = try validate([("Milch", "Kühlregal"), ("Sojasauce", "Vorrat & Konserven"), ("Katzenstreu", "Sonstiges")])
        #expect(proposal.changes == [.init(itemName: "Sojasauce", fromCategory: "Sonstiges", toCategory: "Vorrat & Konserven")])
    }

    @Test func validate_toOther_isAChange() throws {
        let proposal = try validate([("Milch", "Sonstiges")])
        #expect(proposal.changes == [.init(itemName: "Milch", fromCategory: "Kühlregal", toCategory: "Sonstiges")])
    }

    @Test func validate_newCategories_maxThree_andRuleR10() throws {
        let long = String(repeating: "x", count: 31)
        let request = ShoppingSorter.Request(itemNames: ["A", "B", "C", "D", "E", "F"], categoryNames: ["Kühlregal", "Sonstiges"])
        let data = answer([("A", "Tierbedarf"), ("B", "sonstiges"), ("C", long), ("D", "Baby"), ("E", "Garten"), ("F", "Büro")],
                          new: ["Tierbedarf", long, "Baby", "Garten", "Büro"])
        let proposal = try ShoppingSorter.validate(data, request: request, current: ["b": "Kühlregal"])
        #expect(proposal.newCategories == ["Tierbedarf", "Baby", "Garten"])
        #expect(proposal.changes.map(\.itemName) == ["A", "B", "D", "E"])
        #expect(proposal.changes[1].toCategory == "Sonstiges")
    }

    @Test func validate_duplicateItemAndCaseInsensitiveCategory() throws {
        let proposal = try validate([("Sojasauce", "vorrat & konserven"), ("Sojasauce", "Getränke"), ("katzenstreu", "kühlregal")],
                                    new: ["kühlregal"])
        #expect(proposal.newCategories.isEmpty)
        #expect(proposal.changes == [
            .init(itemName: "Sojasauce", fromCategory: "Sonstiges", toCategory: "Vorrat & Konserven"),
            .init(itemName: "Katzenstreu", fromCategory: "Sonstiges", toCategory: "Kühlregal"),
        ])
    }

    @Test func validate_noChanges_isEmptyProposal() throws {
        #expect(try validate([("Milch", "Kühlregal")]).changes.isEmpty)
        #expect(try validate([]).changes.isEmpty)
    }

    @Test func validate_invalidJSON_fails() {
        #expect(throws: ShoppingSorter.Failure.failed) {
            try ShoppingSorter.validate(Data("kein JSON".utf8), request: request, current: current)
        }
    }

    // MARK: Failures

    @Test func sort_failures_mapLikeMealEstimator() async {
        let cases: [(ChatGPTError, ShoppingSorter.Failure)] = [
            (.network, .network), (.notSignedIn, .signedOut), (.invalidUser, .signedOut), (.usageLimit, .usageLimit),
            (.server(500, nil), .failed),
        ]
        for (error, failure) in cases {
            responder.enqueueFailure(error)
            await #expect(throws: failure) { try await sorter().sort(request, current: current) }
        }
        responder.enqueueEvents([.textDelta(String(decoding: answer([]), as: UTF8.self))])  // no `completed`
        await #expect(throws: ShoppingSorter.Failure.failed) { try await sorter().sort(request, current: current) }
        responder.enqueue("kein JSON")
        await #expect(throws: ShoppingSorter.Failure.failed) { try await sorter().sort(request, current: current) }
        #expect(Set([ShoppingSorter.Failure.consentMissing, .network, .signedOut, .usageLimit, .failed].map(\.message)).count == 5)
    }

    @Test func sort_timeout_fails_andLateAnswerIsNotUsed() async {
        let slow = SlowResponder(answer: String(decoding: answer([("Sojasauce", "Getränke")]), as: UTF8.self),
                                 delay: .milliseconds(300))
        await #expect(throws: ShoppingSorter.Failure.failed) {
            try await sorter(slow, timeout: .milliseconds(50)).sort(request, current: current)
        }
    }

    // MARK: Result sheet and applying

    @Test func selection_deselectedNewCategory_dropsItsItems() {
        let proposal = ShoppingSorter.Proposal(newCategories: ["Tierbedarf", "Baby"], changes: [
            .init(itemName: "Katzenstreu", fromCategory: "Sonstiges", toCategory: "Tierbedarf"),
            .init(itemName: "Windeln", fromCategory: "Sonstiges", toCategory: "Baby"),
            .init(itemName: "Reis", fromCategory: "Sonstiges", toCategory: "Vorrat & Konserven"),
        ])
        let selected = ShoppingSortResultSheet.selection(proposal: proposal, deselectedCategories: ["Tierbedarf"],
                                                         deselectedItems: ["reis"])
        #expect(selected.newCategories == ["Baby"])
        #expect(selected.changes.map(\.itemName) == ["Windeln"])
    }

    @Test func apply_storesAIAssignments_keepsManualOnes_writesNoReminder() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)], records: [
            ReminderRecord(id: "1", title: "Sojasauce", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "shop", lastModified: nil),
            ReminderRecord(id: "2", title: "Katzenstreu", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "shop", lastModified: nil),
            ReminderRecord(id: "3", title: "Milch", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "shop", lastModified: nil),
        ])
        let categories = ShoppingCategoryStore(context: container.mainContext, settings: settings)
        categories.seedIfNeeded()
        let model = ShoppingModel(store: store, settings: settings, categories: categories)
        await model.reload()
        let pantry = try #require(categories.categories().first { $0.builtinKey == "pantry" })
        let drinks = try #require(categories.categories().first { $0.builtinKey == "drinks" })
        categories.assign(nameKey: "milch", to: drinks.id, manual: true)

        ShoppingSorter.apply(ShoppingSorter.Proposal(newCategories: ["Tierbedarf"], changes: [
            .init(itemName: "Sojasauce", fromCategory: "Sonstiges", toCategory: "Vorrat & Konserven"),
            .init(itemName: "Katzenstreu", fromCategory: "Haushalt", toCategory: "Tierbedarf"),
            .init(itemName: "Milch", fromCategory: "Getränke", toCategory: "Sonstiges"),
        ]), categories: categories, model: model)

        let pets = try #require(categories.categories().last)
        #expect(pets.name == "Tierbedarf" && pets.sortIndex == 10)
        #expect(categories.assignments()["sojasauce"] == ShoppingAssignmentInfo(categoryID: pantry.id, isManual: false))
        #expect(categories.assignments()["katzenstreu"] == ShoppingAssignmentInfo(categoryID: pets.id, isManual: false))
        #expect(categories.assignments()["milch"] == ShoppingAssignmentInfo(categoryID: drinks.id, isManual: true))
        #expect(model.sections.first { $0.categoryID == pets.id }?.items.map(\.name) == ["Katzenstreu"])
        #expect(store.saveCount == 0 && store.createCount == 0)
    }

    @Test func currentCategories_mapsKeysToSectionNames() {
        let chilled = ShoppingCategoryInfo(id: UUID(), name: "Kühlregal", sortIndex: 0, builtinKey: "chilled")
        let sections = [ShoppingSection(categoryID: chilled.id, items: [ShoppingItem(id: "1", name: "Milch")]),
                        ShoppingSection(categoryID: nil, items: [ShoppingItem(id: "2", name: "Sojasauce")])]
        #expect(ShoppingSorter.currentCategories(sections: sections, categories: [chilled])
                == ["milch": "Kühlregal", "sojasauce": "Sonstiges"])
    }
}
