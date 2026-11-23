import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
final class RecognitionSessionHarness {
    var recognizers: [FakeSpeechRecognizer] = []
    var events: [RecognitionSession.Event] = []
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    lazy var session: RecognitionSession = {
        let session = RecognitionSession(makeRecognizer: {
            let recognizer = FakeSpeechRecognizer()
            self.recognizers.append(recognizer)
            return recognizer
        }, now: { self.clock })
        session.onEvent = { self.events.append($0) }
        return session
    }()

    var recognizer: FakeSpeechRecognizer { recognizers.last! }
    var ends: [RecognitionSession.Event] {
        events.filter { if case .finished = $0 { true } else if case .failed = $0 { true } else { false } }
    }

    /// Waits until the session reported `.started` `count` times in total.
    func waitForStarted(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("\(count) started event(s)", sourceLocation: sourceLocation) {
            events.filter { $0 == .started }.count == count
        }
    }

    func waitForEnds(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("\(count) end event(s)", sourceLocation: sourceLocation) { ends.count == count }
    }

    /// Gives queued work a chance to run before a test asserts that something did NOT happen. A turn count cannot prove
    /// absence, but it cannot make a test fail spuriously either; positive expectations use `awaitCondition`.
    func drain() async { for _ in 0..<50 { await Task.yield() } }
}

@MainActor
struct RecognitionSessionTests {
    @Test func start_reportsStartedAndText() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.waitForStarted()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await awaitCondition("the text event") { harness.events.count == 2 }
        #expect(harness.events == [.started, .text(final: "Hallo", volatile: "")])
        #expect(harness.session.isActive)
    }

    @Test func stop_endsExactlyOnce() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.waitForStarted()
        harness.recognizer.finalOnStop = "Fertig."
        harness.session.stop()
        harness.session.stop()
        await harness.waitForEnds(1)
        harness.clock += 10
        harness.session.tick()
        #expect(harness.ends == [.finished])
        #expect(harness.events.contains(.text(final: "Fertig.", volatile: "")))
        #expect(!harness.session.isActive)
    }

    @Test func stuckStop_isGivenUpAfterTimeout() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.waitForStarted()
        harness.recognizer.ignoresStop = true
        harness.session.stop()
        await awaitCondition("the recognizer received the stop") { harness.recognizer.stops == 1 }
        harness.clock += 2.9
        harness.session.tick()
        #expect(harness.ends.isEmpty)
        harness.clock += 0.1
        harness.session.tick()
        await awaitCondition("the recognizer was cancelled") { harness.recognizer.cancels >= 1 }
        #expect(harness.ends == [.finished])
        #expect(harness.recognizer.cancels >= 1)
    }

    @Test func cancel_reportsNothing_andReleasesRecognizer() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.waitForStarted()
        harness.session.cancel()
        await awaitCondition("the recognizer was cancelled") { harness.recognizer.cancels == 1 }
        harness.recognizer.send(.text(final: "spät", volatile: ""))
        await harness.drain()
        #expect(harness.events == [.started])
        #expect(harness.recognizer.cancels == 1)
    }

    @Test func cancelWhileStarting_releasesMicrophone() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        harness.session.cancel()
        await awaitCondition("the recognizer was cancelled") { harness.recognizer.cancels >= 1 }
        await harness.drain()
        #expect(harness.events.isEmpty)
        #expect(harness.recognizer.cancels >= 1)
    }

    @Test func restart_cancelsOldBeforeNew_andDropsItsEvents() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.waitForStarted()
        let old = harness.recognizer
        harness.session.start(.english)
        await harness.waitForStarted(2)
        #expect(old.cancels == 1)
        old.send(.text(final: "alt", volatile: ""))
        harness.recognizer.send(.text(final: "new", volatile: ""))
        await awaitCondition("the text of the new recognizer") { harness.events.contains(.text(final: "new", volatile: "")) }
        #expect(harness.recognizer.started == [.english])
        #expect(!harness.events.contains(.text(final: "alt", volatile: "")))
        #expect(harness.events.contains(.text(final: "new", volatile: "")))
    }

    @Test func failure_endsOnce() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.waitForStarted()
        harness.recognizer.send(.failed(.interrupted))
        await harness.waitForEnds(1)
        #expect(harness.ends == [.failed(.interrupted)])
        #expect(!harness.session.isActive)
    }
}
