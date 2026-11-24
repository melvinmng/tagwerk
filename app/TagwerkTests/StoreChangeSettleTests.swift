import Testing
@testable import Tagwerk

struct StoreChangeSettleTests {
    @Test func noEchoYet_isNotSettled() {
        #expect(StoreChangeSettle.state(handled: 4, handledBeforeSeed: 4, isHandling: false, quietFor: 3, waited: 3) == .waiting)
    }

    @Test func echoInProgress_isNotSettled() {
        #expect(StoreChangeSettle.state(handled: 4, handledBeforeSeed: 4, isHandling: true, quietFor: 3, waited: 3) == .waiting)
        #expect(StoreChangeSettle.state(handled: 5, handledBeforeSeed: 4, isHandling: true, quietFor: 3, waited: 3) == .waiting)
    }

    @Test func echoHandledButNotQuietLongEnough_isNotSettled() {
        #expect(StoreChangeSettle.state(handled: 5, handledBeforeSeed: 4, isHandling: false, quietFor: 0.2, waited: 1) == .waiting)
    }

    @Test func echoHandledAndQuiet_isSettled() {
        #expect(StoreChangeSettle.state(handled: 5, handledBeforeSeed: 4, isHandling: false, quietFor: 0.5, waited: 1) == .settled)
        #expect(StoreChangeSettle.state(handled: 7, handledBeforeSeed: 4, isHandling: false, quietFor: 2, waited: 4) == .settled)
    }

    @Test func limitReached_endsTheWaitEvenWithoutEcho() {
        #expect(StoreChangeSettle.state(handled: 4, handledBeforeSeed: 4, isHandling: false, quietFor: 10, waited: 10) == .timedOut)
        #expect(StoreChangeSettle.state(handled: 5, handledBeforeSeed: 4, isHandling: true, quietFor: 0, waited: 10.5) == .timedOut)
    }
}
