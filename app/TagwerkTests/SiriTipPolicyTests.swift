import Testing
@testable import Tagwerk

struct SiriTipPolicyTests {
    @Test func policy_showsTheTipUntilItIsDone() {
        #expect(SiriTipPolicy.isVisible(done: false, isUITest: false))
    }

    @Test func policy_hidesAfterDismissal() {
        #expect(!SiriTipPolicy.isVisible(done: true, isUITest: false))
    }

    @Test func policy_hidesInUITests() {
        #expect(!SiriTipPolicy.isVisible(done: false, isUITest: true))
    }
}
