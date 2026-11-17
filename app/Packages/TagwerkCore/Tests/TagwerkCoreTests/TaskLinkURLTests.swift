import Foundation
import Testing
@testable import TagwerkCore

struct TaskLinkURLTests {
    @Test func taskLinkURL_roundTripsGitHubNodeID() {
        let id = TaskID(source: .github, rawValue: "I_kwDO/AbC=_x")
        let url = TaskLinkURL.make(id)
        #expect(url.scheme == "tagwerk")
        #expect(url.host() == "task")
        #expect(TaskLinkURL.parse(url) == id)
    }

    @Test func taskLinkURL_reminderAndLocal() {
        for id in [TaskID(source: .reminders, rawValue: "x-apple-reminder://ABC-123"), TaskID(source: .local, rawValue: UUID().uuidString)] {
            #expect(TaskLinkURL.parse(TaskLinkURL.make(id)) == id)
        }
    }

    @Test func taskLinkURL_rejectsForeignURL() {
        #expect(TaskLinkURL.parse(URL(string: "https://github.com/a/b/issues/1")!) == nil)
        #expect(TaskLinkURL.parse(URL(string: "tagwerk://task/unknown/1")!) == nil)
        #expect(TaskLinkURL.parse(URL(string: "tagwerk://other/github/1")!) == nil)
    }

    @Test func taskID_keyRoundTrip() {
        let id = TaskID(source: .github, rawValue: "I_1:with:colons")
        #expect(id.key == "github:I_1:with:colons")
        #expect(TaskID(key: id.key) == id)
        #expect(TaskID(key: "nonsense") == nil)
    }
}
