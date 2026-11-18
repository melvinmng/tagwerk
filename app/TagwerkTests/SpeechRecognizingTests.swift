import Foundation
import Testing
@testable import Tagwerk

struct SpeechRecognizingTests {
    @Test func accumulator_joinsFinalAndVolatile() {
        var accumulator = TranscriptAccumulator()
        accumulator.add("Leg die", isFinal: false)
        #expect(accumulator.event == .text(final: "", volatile: "Leg die"))
        accumulator.add("Leg die Mail", isFinal: true)
        accumulator.add("auf sechzehn", isFinal: false)
        #expect(accumulator.event == .text(final: "Leg die Mail", volatile: "auf sechzehn"))
        #expect(accumulator.full == "Leg die Mail auf sechzehn")
        accumulator.add(" auf 16 Uhr.", isFinal: true)
        #expect(accumulator.full == "Leg die Mail auf 16 Uhr.")
    }

    @Test func level_mapsRMSToUnitRange() {
        let silence: [Float] = Array(repeating: 0, count: 8)
        let loud: [Float] = Array(repeating: 1, count: 8)
        let quiet: [Float] = Array(repeating: 0.0001, count: 8)
        #expect(silence.withUnsafeBufferPointer { AudioLevel.unit(fromRMSOf: $0) } == 0)
        #expect(loud.withUnsafeBufferPointer { AudioLevel.unit(fromRMSOf: $0) } == 1)
        #expect(quiet.withUnsafeBufferPointer { AudioLevel.unit(fromRMSOf: $0) } == 0)
    }
}
