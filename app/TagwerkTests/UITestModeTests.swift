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

    // MARK: Direct jump to a screen (-TagwerkUITestScreen)

    @Test func screenArgument_namesTheKnownScreens() {
        let names = ["settings.languages", "settings.ai.voice", "settings.capture", "settings.shopping", "settings.siri"]
        #expect(UITestScreen.allCases.map(\.rawValue) == names)
        for name in names {
            let screen = UITestScreen.named(in: ["-TagwerkUITest", UITestMode.screenArgument, name])
            #expect(screen?.rawValue == name)
        }
    }

    @Test func screenArgument_unknownNameMissingValueAndMissingArgumentGiveNoScreen() {
        #expect(UITestScreen.named(in: [UITestMode.screenArgument, "settings.unknown"]) == nil)
        #expect(UITestScreen.named(in: [UITestMode.screenArgument]) == nil)
        #expect(UITestScreen.named(in: ["-TagwerkUITest"]) == nil)
        // The value belongs to the argument that precedes it, not to any other argument.
        #expect(UITestScreen.named(in: ["settings.siri", UITestMode.screenArgument]) == nil)
    }

    @Test func screenArgument_isIgnoredOutsideTheUITestMode() {
        // The unit test host runs without `-TagwerkUITest`: whatever the arguments say, the app must not jump anywhere.
        #expect(UITestMode.screen == nil)
    }

    @Test func settingsScreens_openTheirPageOnTheSettingsStack() {
        #expect(UITestScreen.settingsLanguages.settingsPath == [.languages])
        // The voice settings sit one level below "KI".
        #expect(UITestScreen.settingsAIVoice.settingsPath == [.ai, .aiVoice])
        #expect(UITestScreen.settingsCapture.settingsPath == [.capture])
        #expect(UITestScreen.settingsShopping.settingsPath == [.shopping])
        #expect(UITestScreen.settingsSiri.settingsPath == [.siri])
    }
}
