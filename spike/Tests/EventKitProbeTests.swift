import EventKit
import XCTest
@testable import TagwerkSpike

final class EventKitProbeTests: XCTestCase {
    func test_describe_deniedStatus_isReadable() {
        XCTAssertTrue(EventKitProbe.describe(status: .denied).contains("verweigert"))
    }

    func test_describe_writeOnly_isNotOk() {
        XCTAssertFalse(EventKitProbe.isSufficient(.writeOnly))
        XCTAssertTrue(EventKitProbe.isSufficient(.fullAccess))
    }
}
