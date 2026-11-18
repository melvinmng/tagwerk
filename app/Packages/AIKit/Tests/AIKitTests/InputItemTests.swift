import Foundation
import Testing
@testable import AIKit

struct InputItemTests {
    @Test func userImage_requestJSON_hasTextAndInputImageDataURL() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        let json = InputItem.userImage(text: "halbe Portion", jpeg: jpeg).requestJSON
        #expect(json["role"] as? String == "user")
        let content = try #require(json["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[0]["text"] as? String == "halbe Portion")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["image_url"] as? String == "data:image/jpeg;base64,\(jpeg.base64EncodedString())")
    }

    @Test func userImage_emptyText_onlyImage() throws {
        let json = InputItem.userImage(text: "  ", jpeg: Data([1])).requestJSON
        let content = try #require(json["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content[0]["type"] as? String == "input_image")
    }

    @Test func storedHistory_ofExistingCases_stillDecodes() throws {
        let stored = try JSONEncoder().encode([InputItem.user("Hallo"), .assistant("Hi")])
        let decoded = try JSONDecoder().decode([InputItem].self, from: stored)
        #expect(decoded == [.user("Hallo"), .assistant("Hi")])
    }
}
