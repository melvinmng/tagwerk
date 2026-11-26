import Testing
@testable import Tagwerk

struct SettingsDestinationTests {
    @Test func path_endsWithTheDestinationItself() {
        for destination in SettingsDestination.allCases {
            #expect(destination.path.last == destination)
        }
    }

    @Test func path_listsTheParentFirst() {
        #expect(SettingsDestination.aiVoice.path == [.ai, .aiVoice])
        #expect(SettingsDestination.bibleStudy.path == [.routines, .bibleStudy])
        #expect(SettingsDestination.capture.path == [.capture])
    }

    @Test func path_hasNoRepeatedPage() {
        for destination in SettingsDestination.allCases {
            #expect(Set(destination.path).count == destination.path.count)
        }
    }

    @Test func title_isNeverEmpty() {
        for destination in SettingsDestination.allCases {
            #expect(!String(localized: destination.title).isEmpty)
        }
    }
}
