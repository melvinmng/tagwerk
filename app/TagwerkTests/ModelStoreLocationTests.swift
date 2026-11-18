import Foundation
import SwiftData
import Testing
@testable import Tagwerk

/// Phase 4 adds an App Group; the SwiftData store must stay at its old place (no move, no apparent data loss).
struct ModelStoreLocationTests {
    @Test func persistentStore_staysOutOfTheAppGroupContainer() throws {
        let url = ModelContainerFactory.persistentConfiguration().url
        #expect(!url.path.contains("/Shared/AppGroup/"))
        #expect(!url.path.contains("/Group Containers/"))
        let applicationSupport = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        #expect(url.path.hasPrefix(applicationSupport.path))
    }
}
