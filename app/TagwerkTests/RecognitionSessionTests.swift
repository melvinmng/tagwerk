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

    func settle() async { for _ in 0..<20 { await Task.yield() } }
}

@MainActor
struct RecognitionSessionTests {
    @Test func start_reportsStartedAndText() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.settle()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.settle()
        #expect(harness.events == [.started, .text(final: "Hallo", volatile: "")])
        #expect(harness.session.isActive)
    }

    @Test func stop_endsExactlyOnce() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.settle()
        harness.recognizer.finalOnStop = "Fertig."
        harness.session.stop()
        harness.session.stop()
        await harness.settle()
        harness.clock += 10
        harness.session.tick()
        #expect(harness.ends == [.finished])
        #expect(harness.events.contains(.text(final: "Fertig.", volatile: "")))
        #expect(!harness.session.isActive)
    }

    @Test func stuckStop_isGivenUpAfterTimeout() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.settle()
        harness.recognizer.ignoresStop = true
        harness.session.stop()
        await harness.settle()
        harness.clock += 2.9
        harness.session.tick()
        #expect(harness.ends.isEmpty)
        harness.clock += 0.1
        harness.session.tick()
        await harness.settle()
        #expect(harness.ends == [.finished])
        #expect(harness.recognizer.cancels >= 1)
    }

    @Test func cancel_reportsNothing_andReleasesRecognizer() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.settle()
        harness.session.cancel()
        await harness.settle()
        harness.recognizer.send(.text(final: "spät", volatile: ""))
        await harness.settle()
        #expect(harness.events == [.started])
        #expect(harness.recognizer.cancels == 1)
    }

    @Test func cancelWhileStarting_releasesMicrophone() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        harness.session.cancel()
        await harness.settle()
        #expect(harness.events.isEmpty)
        #expect(harness.recognizer.cancels >= 1)
    }

    @Test func restart_cancelsOldBeforeNew_andDropsItsEvents() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.settle()
        let old = harness.recognizer
        harness.session.start(.english)
        await harness.settle()
        #expect(old.cancels == 1)
        old.send(.text(final: "alt", volatile: ""))
        harness.recognizer.send(.text(final: "new", volatile: ""))
        await harness.settle()
        #expect(harness.recognizer.started == [.english])
        #expect(!harness.events.contains(.text(final: "alt", volatile: "")))
        #expect(harness.events.contains(.text(final: "new", volatile: "")))
    }

    @Test func failure_endsOnce() async {
        let harness = RecognitionSessionHarness()
        harness.session.start(.german)
        await harness.settle()
        harness.recognizer.send(.failed(.interrupted))
        await harness.settle()
        #expect(harness.ends == [.failed(.interrupted)])
        #expect(!harness.session.isActive)
    }
}
