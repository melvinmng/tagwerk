import Foundation
import Testing
@testable import TagwerkCore

struct NoteFolderSectionsTests {
    private func folder(_ name: String, role: NoteFolderRole? = nil, parent: NoteFolderInfo? = nil, order: Int = 0) -> NoteFolderInfo {
        NoteFolderInfo(id: UUID(), name: name, parentID: parent?.id, order: order, role: role)
    }

    private func sections(_ folders: [NoteFolderInfo]) -> [NoteFolderSections.Section] {
        NoteFolderSections.sections(NoteFolderRules.tree(folders))
    }

    @Test func sections_orderIsOwnRoutinesPersonal() {
        let result = sections([folder("Tagebuch", role: .journal), folder("Arbeit"), folder("Tagesstart", role: .morningRoutine)])
        #expect(result.map(\.kind) == [.own, .routines, .personal])
        #expect(result[0].folders.map(\.folder.name) == ["Arbeit"])
        #expect(result[1].folders.map(\.folder.name) == ["Tagesstart"])
        #expect(result[2].folders.map(\.folder.name) == ["Tagebuch"])
    }

    @Test func sections_routinesFollowFixedRoleOrder() {
        // The stored order of the folders must not decide: the roles do.
        let result = sections([
            folder("Dream Log", role: .dreamLog, order: 0),
            folder("Tagesabschluss", role: .eveningRoutine, order: 1),
            folder("Tagesstart", role: .morningRoutine, order: 2),
            folder("Brain Dump", role: .brainDump, order: 3)
        ])
        #expect(result[1].folders.map(\.folder.role) == [.brainDump, .morningRoutine, .eveningRoutine, .dreamLog])
    }

    @Test func sections_personalFollowsFixedRoleOrder() {
        let result = sections([folder("Bible Study", role: .bibleStudy, order: 0), folder("Tagebuch", role: .journal, order: 1)])
        #expect(result[2].folders.map(\.folder.role) == [.journal, .bibleStudy])
    }

    @Test func sections_ownFoldersAreFlattenedWithDepth() {
        let work = folder("Arbeit")
        let plans = folder("Pläne", parent: work)
        let result = sections([plans, work, folder("Haus", order: 1)])
        #expect(result[0].folders.map(\.folder.name) == ["Arbeit", "Pläne", "Haus"])
        #expect(result[0].folders.map(\.depth) == [1, 2, 1])
    }

    @Test func sections_missingSystemFolderIsLeftOut() {
        let result = sections([folder("Tagesstart", role: .morningRoutine)])
        #expect(result[1].folders.map(\.folder.role) == [.morningRoutine])
        #expect(result[2].folders.isEmpty)
        // The sections themselves stay, so the view can show its heading and placeholders.
        #expect(sections([]).map(\.kind) == [.own, .routines, .personal])
    }

    @Test func sections_recipesAndBrainDumpNotInOwn() {
        let result = sections([folder("Rezepte", role: .recipes), folder("Brain Dump", role: .brainDump), folder("Arbeit")])
        #expect(result[0].folders.map(\.folder.name) == ["Arbeit"])
        #expect(result[1].folders.map(\.folder.role) == [.brainDump])
        #expect(!result.flatMap(\.folders).contains { $0.folder.role == .recipes })
    }

    @Test func pinned_returnsRecipesOnlyWhenPresent() {
        let tree = NoteFolderRules.tree([folder("Rezepte", role: .recipes), folder("Arbeit")])
        #expect(NoteFolderSections.pinned(tree).map(\.folder.role) == [.recipes])
        #expect(NoteFolderSections.pinned(NoteFolderRules.tree([folder("Arbeit")])).isEmpty)
    }

    @Test func everyRoleHasExactlyOnePlace() {
        let placed = NoteFolderSections.pinnedRoles + NoteFolderSections.routineRoles + NoteFolderSections.personalRoles
        #expect(Set(placed) == Set(NoteFolderRole.allCases))
        #expect(placed.count == NoteFolderRole.allCases.count)
    }
}
