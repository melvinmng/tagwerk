import Testing
@testable import TagwerkCore

struct ReadAloudPolicyTests {
    @Test func never_neverReads() {
        for spoken in [true, false] {
            for visible in [true, false] {
                #expect(!ReadAloudPolicy.never.readsAutomatically(lastUserMessageWasSpoken: spoken, conversationVisible: visible))
            }
        }
    }

    @Test func afterSpoken_readsOnlyAfterSpokenMessage() {
        #expect(ReadAloudPolicy.afterSpoken.readsAutomatically(lastUserMessageWasSpoken: true, conversationVisible: true))
        #expect(!ReadAloudPolicy.afterSpoken.readsAutomatically(lastUserMessageWasSpoken: false, conversationVisible: true))
    }

    @Test func always_readsWhenVisible() {
        #expect(ReadAloudPolicy.always.readsAutomatically(lastUserMessageWasSpoken: false, conversationVisible: true))
        #expect(ReadAloudPolicy.always.readsAutomatically(lastUserMessageWasSpoken: true, conversationVisible: true))
    }

    @Test func invisibleConversation_neverReads() {
        for policy in ReadAloudPolicy.allCases {
            #expect(!policy.readsAutomatically(lastUserMessageWasSpoken: true, conversationVisible: false))
        }
    }

    @Test func titles_areGerman() {
        #expect(ReadAloudPolicy.never.title == "Nie")
        #expect(ReadAloudPolicy.afterSpoken.title == "Nach gesprochenen Nachrichten")
        #expect(ReadAloudPolicy.always.title == "Immer")
    }

    @Test func rawValues_areStable() {
        #expect(ReadAloudPolicy.allCases.map(\.rawValue) == ["never", "afterSpoken", "always"])
    }
}
