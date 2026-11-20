import Foundation
import SwiftData
import Testing
@testable import Tagwerk

/// The UI test mode changes the store and the demo data; it must never be on by accident.
struct UITestModeTests {
    @Test func inactiveWithoutArgument() {
        #expect(!ProcessInfo.processInfo.arguments.contains(UITestMode.launchArgument))
        #expect(!UITestMode.isActive)
    }

    @Test func inMemoryStore_opensWithTheFullSchema() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
        #expect(container.schema.entities.count == ModelContainerFactory.schema.entities.count)
    }
}
