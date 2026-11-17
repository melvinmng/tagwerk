import XCTest
@testable import TagwerkSpike

final class SmokeTests: XCTestCase {
    func test_appLaunches_bundleIdentifierMatches() {
        let hostBundle = Bundle(for: AppMarker.self)
        XCTAssertTrue(hostBundle.bundleIdentifier?.hasPrefix("com.melvinmng.tagwerk.spike") ?? false)
    }
}
