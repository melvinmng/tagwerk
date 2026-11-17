import FoundationModels
import XCTest
@testable import TagwerkSpike

final class AppleModelProbeTests: XCTestCase {
    func test_describe_unavailableReasons_areReadableGerman() {
        XCTAssertTrue(AppleModelProbe.describe(.unavailable(.appleIntelligenceNotEnabled)).contains("Apple Intelligence"))
        XCTAssertTrue(AppleModelProbe.describe(.unavailable(.modelNotReady)).contains("lädt"))
        XCTAssertTrue(AppleModelProbe.describe(.unavailable(.deviceNotEligible)).contains("Gerät"))
        XCTAssertEqual(AppleModelProbe.describe(.available), "verfügbar")
    }
}
