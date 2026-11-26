import Foundation
import SwiftData
import Testing
import TagwerkCore
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
        let names = ["settings.languages", "settings.ai.voice", "settings.capture", "settings.shopping", "settings.siri",
                     "github.repositoryPicker", "github.projectPicker"]
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

    @Test func pickerScreens_areSheetsWithoutASettingsPage() {
        #expect(UITestScreen.githubRepositoryPicker.isPickerSheet && UITestScreen.githubProjectPicker.isPickerSheet)
        #expect(UITestScreen.githubRepositoryPicker.settingsPath.isEmpty)
        #expect(!UITestScreen.settingsSiri.isPickerSheet)
    }

    @Test func settingsScreens_openTheirPageOnTheSettingsStack() {
        #expect(UITestScreen.settingsLanguages.settingsPath == [.languages])
        // The voice settings sit one level below "KI".
        #expect(UITestScreen.settingsAIVoice.settingsPath == [.ai, .aiVoice])
        #expect(UITestScreen.settingsCapture.settingsPath == [.capture])
        #expect(UITestScreen.settingsShopping.settingsPath == [.shopping])
        #expect(UITestScreen.settingsSiri.settingsPath == [.siri])
    }

    // MARK: Pinned weekday (-TagwerkUITestWeekday)

    @Test func weekday_withoutPin_isTheActualOne() {
        for actual in 1...7 { #expect(UITestMode.weekday(actual: actual, pinned: nil) == actual) }
    }

    @Test func weekday_pinned_replacesTheActualOneOnEveryDay() {
        for actual in 1...7 { #expect(UITestMode.weekday(actual: actual, pinned: 1) == 1) }
        #expect(UITestMode.weekday(actual: 2, pinned: 7) == 7)
    }

    @Test func weekday_pinnedOutsideTheRange_isIgnored() {
        #expect(UITestMode.weekday(actual: 4, pinned: 0) == 4)
        #expect(UITestMode.weekday(actual: 4, pinned: 8) == 4)
        #expect(UITestMode.weekday(actual: 4, pinned: -1) == 4)
    }

    @Test func weekdayOfDay_withoutArgument_followsTheCalendar() {
        // The unit test host runs without `-TagwerkUITest`: the pin is never active there. 2026-11-22 is a Sunday, 2026-11-23 a Monday,
        // in a calendar with a fixed time zone, so the result does not depend on the zone of the machine.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        #expect(UITestMode.weekdayOverride == nil)
        #expect(UITestMode.weekday(of: PlanDay(year: 2026, month: 11, day: 22), calendar: calendar) == 1)
        #expect(UITestMode.weekday(of: PlanDay(year: 2026, month: 11, day: 23), calendar: calendar) == 2)
    }
}
