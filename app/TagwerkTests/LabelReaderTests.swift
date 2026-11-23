import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Reading a nutrition table from a photo (decision LM3b): consent first, one request on a tap, a proposal that stays unknown where
/// the label says nothing.
@MainActor
struct LabelReaderTests {
    let responder = FakePlanResponder()
    final class Counter { var value = 0 }

    static let answer = #"{"table_found":true,"product_name":"Skyr natur","basis":"per_100g","serving_grams":null,"kcal":62,"kj":null,"protein_g":11,"carbs_g":4,"fat_g":0.2,"fiber_g":null,"sugar_g":4,"saturated_fat_g":0.1,"salt_g":0.1}"#
    static let noTable = #"{"table_found":false,"product_name":null,"basis":"per_100g","serving_grams":null,"kcal":null,"kj":null,"protein_g":null,"carbs_g":null,"fat_g":null,"fiber_g":null,"sugar_g":null,"saturated_fat_g":null,"salt_g":null}"#
    let jpeg = Data([0xFF, 0xD8, 0x01])

    func make(_ responder: any ResponseStreaming, consent: Bool = true, counter: Counter = Counter(),
              timeout: Duration = .seconds(30)) -> LabelReader {
        LabelReader(responder: responder, model: { counter.value += 1; return "gpt-test" }, hasConsent: { consent }, timeout: timeout)
    }

    @Test func labelReader_requiresMealConsent() async {
        let counter = Counter()
        let reader = make(responder, consent: false, counter: counter)
        await #expect(throws: LabelReader.Failure.consentMissing) { try await reader.read(jpeg: jpeg) }
        #expect(counter.value == 0, "not even the model list is loaded without consent")
        #expect(responder.calls.isEmpty)
    }

    @Test func labelReader_nullFieldsStayUnknown() async throws {
        responder.enqueue(Self.answer)
        let reading = try await make(responder).read(jpeg: jpeg)
        #expect(reading.food.nutrients.fiber == nil)
        #expect(reading.food.nutrients.sugar == 4)
        #expect(reading.food.name == "Skyr natur" && reading.food.kcal == 62 && !reading.energyUnknown)
        #expect(reading.food.origin == .label)
    }

    @Test func labelReader_noTable_reportsNothingRecognized() async {
        responder.enqueue(Self.noTable)
        let reader = make(responder)
        await #expect(throws: LabelReader.Failure.nothingRecognized) { try await reader.read(jpeg: jpeg) }
    }

    @Test func labelReader_sendsOnePhotoRequest_withTheStrictSchema() async throws {
        responder.enqueue(Self.answer)
        _ = try await make(responder).read(jpeg: jpeg)
        #expect(responder.calls.count == 1)
        #expect(responder.calls.first?.schema == "nutrition_label")
        guard case .userImage(let text, let sent)? = responder.calls.first?.input.first else {
            Issue.record("the request is not a photo request")
            return
        }
        #expect(sent == jpeg)
        #expect(text == LabelReader.request, "nothing but the fixed request goes along with the photo")
        let schema = try #require(try JSONSerialization.jsonObject(with: LabelReader.schema) as? [String: Any])
        let required = try #require(schema["required"] as? [String])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(required) == Set(properties.keys), "the strict format wants every field, null where unknown")
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test func labelReader_instructions_askForNullInsteadOfGuessing() {
        #expect(LabelReader.instructions.contains("null"))
        #expect(!LabelReader.instructions.lowercased().contains("health"))
    }

    @Test func labelReader_invalidAnswer_isAFailure() async {
        responder.enqueue(#"{"table_found":true}"#)
        let reader = make(responder)
        await #expect(throws: LabelReader.Failure.failed) { try await reader.read(jpeg: jpeg) }
    }

    @Test func labelReader_networkError_isReported() async {
        responder.enqueueFailure(.network)
        let reader = make(responder)
        await #expect(throws: LabelReader.Failure.network) { try await reader.read(jpeg: jpeg) }
    }
}
