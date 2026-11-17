import XCTest
@testable import TagwerkSpike

final class HealthKitProbeTests: XCTestCase {
    func test_summarize_noData_isOkWithZero() {
        let result = HealthKitProbe.summarize(steps: nil, workouts: 0)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.detail.contains("0"))
    }
}

import HealthKit

final class HealthKitNoDataTests: XCTestCase {
    func test_isNoData_recognizesHealthKitNoDataError() {
        XCTAssertTrue(HealthKitProbe.isNoData(HKError(.errorNoData)))
        XCTAssertFalse(HealthKitProbe.isNoData(HKError(.errorAuthorizationDenied)))
    }
}
