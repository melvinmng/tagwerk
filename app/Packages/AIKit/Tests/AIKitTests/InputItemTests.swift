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

    @Test func userImages_requestJSON_hasTextAndOneInputImagePerPhotoInOrder() throws {
        let first = Data([1, 2]), second = Data([3, 4]), third = Data([5, 6])
        let json = InputItem.userImages(text: "Seiten", jpegs: [first, second, third]).requestJSON
        #expect(json["role"] as? String == "user")
        let content = try #require(json["content"] as? [[String: Any]])
        #expect(content.count == 4)
        #expect(content[0]["type"] as? String == "input_text")
        let urls = content.dropFirst().map { $0["image_url"] as? String }
        #expect(urls == [first, second, third].map { "data:image/jpeg;base64,\($0.base64EncodedString())" })
        #expect(content.dropFirst().allSatisfy { $0["type"] as? String == "input_image" })
    }

    @Test func userImages_singlePhoto_equalsUserImage() throws {
        let jpeg = Data([7, 7])
        let single = InputItem.userImage(text: "x", jpeg: jpeg).requestJSON["content"] as? [[String: Any]]
        let many = InputItem.userImages(text: "x", jpegs: [jpeg]).requestJSON["content"] as? [[String: Any]]
        #expect(single?.map { $0["type"] as? String } == many?.map { $0["type"] as? String })
        #expect(single?.last?["image_url"] as? String == many?.last?["image_url"] as? String)
    }

    @Test func storedHistory_ofExistingCases_stillDecodes() throws {
        let stored = try JSONEncoder().encode([InputItem.user("Hallo"), .assistant("Hi")])
        let decoded = try JSONDecoder().decode([InputItem].self, from: stored)
        #expect(decoded == [.user("Hallo"), .assistant("Hi")])
    }
}
