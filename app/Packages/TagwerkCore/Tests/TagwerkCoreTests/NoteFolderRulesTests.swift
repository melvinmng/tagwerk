import Foundation
import Testing
@testable import TagwerkCore

struct NoteFolderRulesTests {
    private func folder(_ name: String, parent: NoteFolderInfo? = nil, order: Int = 0, role: NoteFolderRole? = nil) -> NoteFolderInfo {
        NoteFolderInfo(id: UUID(), name: name, parentID: parent?.id, order: order, role: role)
    }

    @Test func tree_ordersLevelsAndNestsChildren() {
        let work = folder("Arbeit", order: 1)
        let home = folder("Haus", order: 0)
        let plans = folder("Pläne", parent: work)
        let tree = NoteFolderRules.tree([work, plans, home])
        #expect(tree.map(\.folder.name) == ["Haus", "Arbeit"])
        #expect(tree[1].children.map(\.folder.name) == ["Pläne"])
        #expect(tree[1].children[0].depth == 2)
        #expect(tree.flatMap(\.flattened).map(\.folder.name) == ["Haus", "Arbeit", "Pläne"])
    }

    @Test func tree_sortsByNameWhenOrderIsEqual() {
        let tree = NoteFolderRules.tree([folder("b"), folder("A"), folder("c")])
        #expect(tree.map(\.folder.name) == ["A", "b", "c"])
    }

    @Test func tree_orphanBecomesTopLevel() {
        let lost = NoteFolderInfo(id: UUID(), name: "Verwaist", parentID: UUID())
        #expect(NoteFolderRules.tree([lost]).map(\.folder.name) == ["Verwaist"])
    }

    @Test func tree_cutsReferenceCycles() {
        var first = folder("A")
        var second = folder("B")
        first.parentID = second.id
        second.parentID = first.id
        // A cycle has no top-level folder; nothing must loop forever.
        #expect(NoteFolderRules.tree([first, second]).isEmpty)
    }

    @Test func depth_andCreateLimit() {
        let one = folder("1")
        let two = folder("2", parent: one)
        let three = folder("3", parent: two)
        let all = [one, two, three]
        #expect(NoteFolderRules.depth(of: three.id, in: all) == 3)
        #expect(NoteFolderRules.canCreateFolder(under: nil, in: all))
        #expect(NoteFolderRules.canCreateFolder(under: two.id, in: all))
        #expect(!NoteFolderRules.canCreateFolder(under: three.id, in: all))
        #expect(!NoteFolderRules.canCreateFolder(under: UUID(), in: all))
    }

    @Test func systemFolders_haveNoSubfolders() {
        let journal = folder("Tagebuch", role: .journal)
        #expect(!NoteFolderRules.canCreateFolder(under: journal.id, in: [journal]))
    }

    @Test func validateMove_rejectsCyclesDepthAndSystemFolders() throws {
        let one = folder("1")
        let two = folder("2", parent: one)
        let other = folder("Anderer")
        let deepParent = folder("X")
        let deepChild = folder("Y", parent: deepParent)
        let deepest = folder("Z", parent: deepChild)
        let system = folder("Tagebuch", role: .journal)
        let all = [one, two, other, deepParent, deepChild, deepest, system]

        try NoteFolderRules.validateMove(two.id, to: nil, in: all)
        try NoteFolderRules.validateMove(two.id, to: other.id, in: all)
        #expect(throws: NoteFolderRules.MoveError.cycle) { try NoteFolderRules.validateMove(one.id, to: two.id, in: all) }
        #expect(throws: NoteFolderRules.MoveError.cycle) { try NoteFolderRules.validateMove(one.id, to: one.id, in: all) }
        // Moving "1" (two levels) below the third level of the X chain would reach depth 5.
        #expect(throws: NoteFolderRules.MoveError.tooDeep) { try NoteFolderRules.validateMove(one.id, to: deepChild.id, in: all) }
        // A one-level folder below the second level reaches exactly depth 3.
        try NoteFolderRules.validateMove(other.id, to: deepChild.id, in: all)
        #expect(throws: NoteFolderRules.MoveError.tooDeep) { try NoteFolderRules.validateMove(other.id, to: deepest.id, in: all) }
        #expect(throws: NoteFolderRules.MoveError.systemFolder) { try NoteFolderRules.validateMove(system.id, to: other.id, in: all) }
        #expect(throws: NoteFolderRules.MoveError.systemFolder) { try NoteFolderRules.validateMove(other.id, to: system.id, in: all) }
        #expect(throws: NoteFolderRules.MoveError.unknownFolder) { try NoteFolderRules.validateMove(UUID(), to: nil, in: all) }
    }

    @Test func validatedName_rules() throws {
        let parent = folder("Eltern")
        let existing = folder("Ideen", parent: parent)
        let all = [parent, existing]
        #expect(try NoteFolderRules.validatedName("  Plan ", parentID: parent.id, in: all) == "Plan")
        #expect(throws: NoteFolderRules.NameError.empty) { try NoteFolderRules.validatedName(" \n", parentID: nil, in: all) }
        #expect(throws: NoteFolderRules.NameError.tooLong) {
            try NoteFolderRules.validatedName(String(repeating: "a", count: NoteFolderRules.nameLimit + 1), parentID: nil, in: all)
        }
        #expect(throws: NoteFolderRules.NameError.duplicate) { try NoteFolderRules.validatedName("ideen", parentID: parent.id, in: all) }
        // The same name is fine on another level, and renaming a folder to its own name is not a duplicate.
        #expect(try NoteFolderRules.validatedName("Ideen", parentID: nil, in: all) == "Ideen")
        #expect(try NoteFolderRules.validatedName("Ideen", parentID: parent.id, in: all, excluding: existing.id) == "Ideen")
    }

    @Test func noteCounts_includeSubfolders() {
        let work = folder("Arbeit")
        let plans = folder("Pläne", parent: work)
        let other = folder("Haus")
        let counts = NoteFolderRules.noteCounts(folders: [work, plans, other],
                                                noteFolderIDs: [work.id, plans.id, plans.id, nil, other.id])
        #expect(counts[work.id] == 3 && counts[plans.id] == 2 && counts[other.id] == 1)
    }

    @Test func retention_expiresAfterThirtyDays() {
        let calendar = makeCalendar()
        let deleted = instant(2026, 11, 1, 12)
        #expect(!NoteFolderRules.isExpired(deletedAt: deleted, now: instant(2026, 12, 1, 11), calendar: calendar))
        #expect(NoteFolderRules.isExpired(deletedAt: deleted, now: instant(2026, 12, 1, 12), calendar: calendar))
        #expect(NoteFolderRules.daysLeft(deletedAt: deleted, now: instant(2026, 11, 20, 12), calendar: calendar) == 11)
        #expect(NoteFolderRules.daysLeft(deletedAt: deleted, now: instant(2027, 1, 1), calendar: calendar) == 0)
    }

    @Test func sortOrder_pinnedFirstThenByChoice() {
        let old = instant(2026, 1, 1)
        let mid = instant(2026, 6, 1)
        let new = instant(2026, 11, 1)
        let apple = NoteSortKey(isPinned: false, createdAt: new, updatedAt: old, title: "Apfel")
        let banana = NoteSortKey(isPinned: false, createdAt: old, updatedAt: new, title: "banane")
        let cherry = NoteSortKey(isPinned: true, createdAt: mid, updatedAt: mid, title: "Zitrone")
        func sorted(_ order: NoteSortOrder) -> [String] {
            [apple, banana, cherry].sorted { order.precedes($0, $1) }.map(\.title)
        }
        #expect(sorted(.modified) == ["Zitrone", "banane", "Apfel"])
        #expect(sorted(.created) == ["Zitrone", "Apfel", "banane"])
        #expect(sorted(.title) == ["Zitrone", "Apfel", "banane"])
    }
}
