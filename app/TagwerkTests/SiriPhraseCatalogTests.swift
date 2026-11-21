import AppIntents
import Foundation
import Testing
@testable import Tagwerk

/// The list on the page "Siri & Kurzbefehle" against the App Shortcuts the app registers. The phrase texts themselves are
/// compared with `TagwerkIntents.swift` by `scripts/check-strings.py`.
struct SiriPhraseCatalogTests {
    /// The `shortTitle` of every `AppShortcut` in `TagwerkShortcuts`, read by reflection (the type has no public accessor).
    private func registeredShortTitles() -> [String] {
        TagwerkShortcuts.appShortcuts.compactMap { shortcut in
            Mirror(reflecting: shortcut).children
                .first { $0.label == "shortTitle" }
                .flatMap { child in
                    let resource = (child.value as? LocalizedStringResource) ?? (child.value as? LocalizedStringResource?).flatMap { $0 }
                    return resource.map { String(localized: $0) }
                }
        }
    }

    @Test func catalog_listsEveryShortcutOnce() {
        let ids = SiriPhraseCatalog.groups.flatMap(\.phrases).map(\.id)
        #expect(ids.count == 10)
        #expect(Set(ids).count == ids.count, "an entry is listed twice")
        #expect(SiriPhraseCatalog.shortcutCount == TagwerkShortcuts.appShortcuts.count)
        #expect(Set(ids) == Set(registeredShortTitles()), "the list and the registered App Shortcuts differ")
    }

    @Test func catalog_marksForegroundIntents() {
        // Meal, workout, shopping list and dictation bring Tagwerk to the front (`supportedModes == .foreground`).
        let opening = SiriPhraseCatalog.groups.flatMap(\.phrases).filter(\.opensApp).map(\.id)
        #expect(Set(opening) == ["Mahlzeit erfassen", "Training erfassen", "Einkaufsliste zeigen", "Notiz diktieren"])
    }

    @Test func catalog_focusNamesBothActions() throws {
        let focus = try #require(SiriPhraseCatalog.groups.flatMap(\.phrases).first { $0.id == "Fokus" })
        #expect(String(localized: focus.phrase) == "Fokus starten in Tagwerk")
        let alternative = try #require(focus.alternative)
        #expect(String(localized: alternative) == "Fokus beenden in Tagwerk")
    }

    @Test func catalog_hasFourGroupsInTheOrderOfThePage() {
        #expect(SiriPhraseCatalog.groups.map(\.id) == ["capture", "shopping", "day", "notes"])
    }
}
