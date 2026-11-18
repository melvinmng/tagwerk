import AIKit
import Foundation
import ImageIO
import Testing
import UIKit
@testable import Tagwerk

/// A responder whose stream never ends, for the timeout.
private final class HangingResponder: ResponseStreaming, @unchecked Sendable {
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { _ in }
    }
}

/// A responder that fails with a fixed error.
private final class FailingResponder: ResponseStreaming, @unchecked Sendable {
    let error: Error
    init(_ error: Error) { self.error = error }
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

@MainActor
struct MealEstimatorTests {
    let responder = FakePlanResponder()
    static let answer = #"{"title":"Brötchen mit Käse","items":[{"name":"Brötchen","amount":"2 Stück","kcal_min":250,"kcal":300,"kcal_max":350,"protein_g":10,"carbs_g":56,"fat_g":2},{"name":"Käse","amount":"2 Scheiben","kcal_min":150,"kcal":180,"kcal_max":220,"protein_g":12,"carbs_g":0,"fat_g":14}]}"#

    final class Counter { var value = 0 }

    func make(_ responder: any ResponseStreaming, consent: Bool = true, counter: Counter = Counter(),
              timeout: Duration = .seconds(30)) -> MealEstimator {
        MealEstimator(responder: responder, model: { counter.value += 1; return "gpt-test" }, hasConsent: { consent },
                      timeout: timeout)
    }

    @Test func noConsent_sendsNothing_andDoesNotLoadModels() async {
        let counter = Counter()
        let estimator = make(responder, consent: false, counter: counter)
        await #expect(throws: MealEstimator.Failure.consentMissing) {
            try await estimator.estimate(text: "2 Brötchen mit Käse", jpeg: nil)
        }
        #expect(counter.value == 0)
        #expect(responder.calls.isEmpty)
    }

    @Test func textOnly_sendsOneUserItem_withSchema_fixedInstructions() async throws {
        responder.enqueue(Self.answer)
        responder.enqueue(Self.answer)
        let estimator = make(responder)
        let estimate = try await estimator.estimate(text: "2 Brötchen mit Käse", jpeg: nil)
        _ = try await estimator.estimate(text: "Apfel", jpeg: nil)
        #expect(estimate.title == "Brötchen mit Käse")
        #expect(estimate.items.count == 2)
        #expect(estimate.items.allSatisfy { $0.isEstimated })
        let call = try #require(responder.calls.first)
        #expect(call.input == [.user("2 Brötchen mit Käse")])
        #expect(call.schema == "meal_estimate")
        #expect(responder.instructions[0] == MealEstimator.instructions)
        #expect(responder.instructions[1] == MealEstimator.instructions)
    }

    @Test func image_sendsUserImage() async throws {
        responder.enqueue(Self.answer)
        let jpeg = Data([0xFF, 0xD8])
        _ = try await make(responder).estimate(text: "halbe Portion", jpeg: jpeg)
        #expect(responder.calls.first?.input == [.userImage(text: "halbe Portion", jpeg: jpeg)])
    }

    @Test func emptyItems_nothingRecognized() async {
        responder.enqueue(#"{"title":"","items":[]}"#)
        await #expect(throws: MealEstimator.Failure.nothingRecognized) {
            try await make(responder).estimate(text: "Tisch", jpeg: nil)
        }
    }

    @Test func undecodableAnswer_failed() async {
        responder.enqueue("kein JSON")
        await #expect(throws: MealEstimator.Failure.failed) {
            try await make(responder).estimate(text: "Apfel", jpeg: nil)
        }
    }

    @Test func partialAnswer_neverUsed() async {
        responder.enqueueEvents([.textDelta(Self.answer)])  // no .completed
        await #expect(throws: MealEstimator.Failure.failed) {
            try await make(responder).estimate(text: "Apfel", jpeg: nil)
        }
    }

    @Test func timeout_failed() async {
        await #expect(throws: MealEstimator.Failure.failed) {
            try await make(HangingResponder(), timeout: .milliseconds(50)).estimate(text: "Apfel", jpeg: nil)
        }
    }

    @Test func errors_mapToTexts() async {
        let cases: [(Error, MealEstimator.Failure)] = [
            (ChatGPTError.network, .network), (ChatGPTError.notSignedIn, .signedOut), (ChatGPTError.invalidUser, .signedOut),
            (ChatGPTError.usageLimit, .usageLimit), (ChatGPTError.server(500, nil), .failed),
        ]
        for (error, failure) in cases {
            await #expect(throws: failure) { try await make(FailingResponder(error)).estimate(text: "Apfel", jpeg: nil) }
        }
        #expect(MealEstimator.Failure.network.message == "Keine Verbindung. Die Schätzung braucht Internet.")
        #expect(MealEstimator.Failure.nothingRecognized.message
                == "Darin war kein Essen zu erkennen. Beschreib die Mahlzeit genauer oder trag die Werte selbst ein.")
    }
}

struct ImageDownscalerTests {
    private func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(_ data: Data) throws -> (Int, Int, [String: Any]) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        return (properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0,
                properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0, properties)
    }

    @Test func downscale_longEdge1024_noGPS() throws {
        let data = try #require(ImageDownscaler.jpeg(from: image(width: 3000, height: 2000)))
        let (width, height, properties) = try pixelSize(data)
        #expect(width == 1024)
        #expect(height == 683)
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
    }

    @Test func smallImage_notUpscaled() throws {
        let data = try #require(ImageDownscaler.jpeg(from: image(width: 500, height: 400)))
        let (width, height, _) = try pixelSize(data)
        #expect(width == 500 && height == 400)
    }
}
