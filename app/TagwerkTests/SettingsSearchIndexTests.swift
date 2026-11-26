import Foundation
import Testing
@testable import Tagwerk

struct SettingsSearchIndexTests {
    private func ids(_ query: String) -> [String] {
        SettingsSearchIndex.hits(for: query).map(\.id)
    }

    @Test func entries_haveUniqueIds() {
        let ids = SettingsSearchIndex.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func entries_everyDestinationHasAPageEntry() {
        for destination in SettingsDestination.allCases {
            #expect(SettingsSearchIndex.entries.contains { $0.destination == destination && $0.isPage },
                    "No page entry for \(destination)")
        }
    }

    @Test func entries_everyEntryResolvesToAPathOrARowOfTheList() {
        for entry in SettingsSearchIndex.entries {
            let target = entry.target
            #expect(!target.path.isEmpty || target.anchor != nil, "\(entry.id) opens nothing")
            if let destination = entry.destination { #expect(target.path == destination.path) }
            // The path is a chain of pages that exist: every page is a case, so the chain only has to be free of repeats.
            #expect(Set(target.path).count == target.path.count)
        }
    }

    @Test func entries_everyAnchorHasAnEntryAndATitle() {
        for anchor in SettingsAnchor.allCases {
            #expect(SettingsSearchIndex.entries.contains { $0.anchor == anchor }, "No entry for \(anchor)")
            #expect(!String(localized: anchor.title).isEmpty)
        }
    }

    @Test func entries_titlesAreNotEmpty() {
        for entry in SettingsSearchIndex.entries {
            #expect(!String(localized: entry.title).isEmpty, "\(entry.id) has no title")
        }
    }

    @Test func hits_findAPageByItsTitle() {
        #expect(ids("Datensicherung").first == "page.backup")
        #expect(ids("fokus-timer").first == "page.focus")
    }

    @Test func hits_findASettingByAKeyword() {
        #expect(ids("Kalorien").contains("capture.kilocalories"))
        #expect(ids("open food").contains("capture.openFoodFacts"))
        #expect(ids("Pomodoro").contains("focus.pomodoro"))
        #expect(ids("Stimme").contains("page.aiVoice"))
        #expect(ids("Backup").contains("page.backup"))
    }

    @Test func hits_ignoreCaseAndUmlauts() {
        #expect(ids("ERINNERUNGSLISTEN").contains("page.reminderLists"))
        #expect(ids("fahrzeit").contains("page.travel"))
    }

    @Test func hits_openTheMainListForARowWithoutAPage() {
        let hit = SettingsSearchIndex.hits(for: "Puffer").first { $0.id == "buffer.gap" }
        #expect(hit?.target.path == [])
        #expect(hit?.target.anchor == .buffer)
    }

    @Test func hits_nestedPageOpensTheWholePath() {
        let hit = SettingsSearchIndex.hits(for: "Spracheingabe").first { $0.id == "page.aiVoice" }
        #expect(hit?.target.path == [.ai, .aiVoice])
    }

    @Test func hits_showTheWayThroughTheSettings() {
        let hit = SettingsSearchIndex.hits(for: "Open Food Facts").first { $0.id == "capture.openFoodFacts" }
        #expect(hit?.pathText == String(localized: "Erfassen"))
    }

    @Test func hits_noMatchIsEmpty() {
        #expect(SettingsSearchIndex.hits(for: "xyzzy").isEmpty)
    }

    @Test func hits_blankQueryIsEmpty() {
        #expect(SettingsSearchIndex.hits(for: "  ").isEmpty)
    }

    @Test func hits_limitCutsTheList() {
        #expect(SettingsSearchIndex.hits(for: "er", limit: 3).count <= 3)
    }
}
