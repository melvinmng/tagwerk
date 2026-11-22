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

    @Test func role_rawValues_areStable() {
        #expect(NoteFolderRole.journal.rawValue == "journal")
        #expect(NoteFolderRole.bibleStudy.rawValue == "bibleStudy")
        #expect(NoteFolderRole.brainDump.rawValue == "brainDump")
        #expect(NoteFolderRole.morningRoutine.rawValue == "morningRoutine")
        #expect(NoteFolderRole.eveningRoutine.rawValue == "eveningRoutine")
        #expect(NoteFolderRole.dreamLog.rawValue == "dreamLog")
        #expect(NoteFolderRole.recipes.rawValue == "recipes")
        #expect(NoteKind.dream.rawValue == "dream")
    }

    @Test func recipes_acceptsOwnNotes_notPrivate_inDefaultBackup() {
        #expect(NoteFolderRole.recipes.acceptsOwnNotes && !NoteFolderRole.recipes.isPrivate && NoteFolderRole.recipes.isInDefaultBackup)
        #expect(NoteFolderRole.recipes.noteKind == nil)
        #expect(NoteFolderRole.role(for: .free) == nil)
    }

    @Test func role_isPrivate_journalBibleStudyAndDreamLog() {
        #expect(Set(NoteFolderRole.allCases.filter(\.isPrivate)) == [.journal, .bibleStudy, .dreamLog])
    }

    @Test func role_defaultBackup_onlyJournalAndBibleStudyAreLeftOut() {
        #expect(Set(NoteFolderRole.allCases.filter { !$0.isInDefaultBackup }) == [.journal, .bibleStudy])
    }

    @Test func role_agreesWithNoteKind_onPrivacyAndBackup() {
        for role in NoteFolderRole.allCases {
            guard let kind = role.noteKind else { continue }
            #expect(role.isPrivate == kind.isPrivate, "privacy of \(role)")
            #expect(role.isInDefaultBackup == kind.isInDefaultBackup, "backup of \(role)")
        }
        #expect(NoteKind.dream.isPrivate && NoteKind.dream.isInDefaultBackup)
    }

    @Test func role_forKind_findsTheFolderOfThoughtAndDreamNotes() {
        #expect(NoteFolderRole.role(for: .morning) == .morningRoutine)
        #expect(NoteFolderRole.role(for: .evening) == .eveningRoutine)
        #expect(NoteFolderRole.role(for: .dream) == .dreamLog)
        #expect(NoteFolderRole.role(for: .free) == nil)
        #expect(NoteFolderRole.role(for: .journal) == nil)
    }

    @Test func role_noteKind_mapsRoutineFolders() {
        #expect(NoteFolderRole.dreamLog.noteKind == .dream)
        #expect(NoteFolderRole.morningRoutine.noteKind == .morning)
        #expect(NoteFolderRole.eveningRoutine.noteKind == .evening)
        #expect(NoteFolderRole.brainDump.noteKind == nil)
        #expect(NoteFolderRole.journal.noteKind == nil)
    }

    @Test func role_acceptsOwnNotes_onlyRoutineFoldersRefuse() {
        #expect(NoteFolderRole.brainDump.acceptsOwnNotes)
        #expect(!NoteFolderRole.morningRoutine.acceptsOwnNotes)
        #expect(!NoteFolderRole.eveningRoutine.acceptsOwnNotes)
        #expect(!NoteFolderRole.dreamLog.acceptsOwnNotes)
        // Existing behaviour: the folder picker has always offered these two.
        #expect(NoteFolderRole.journal.acceptsOwnNotes && NoteFolderRole.bibleStudy.acceptsOwnNotes)
    }

    @Test func privateFolderIDs_includesSubfolders() {
        // Subfolders below system folders cannot be created in the app (`subfolderBelowSystemFolder_cannotBeCreatedOrMovedThere`);
        // this data is built directly and only guards against future changes and damaged data.
        let journal = folder("Tagebuch", role: .journal)
        let sub = folder("Unter Tagebuch", parent: journal)
        let subSub = folder("Tiefer", parent: sub)
        let free = folder("Arbeit")
        let ids = NoteFolderRules.privateFolderIDs(in: [journal, sub, subSub, free])
        #expect(ids == [journal.id, sub.id, subSub.id])
    }

    @Test func privateFolderIDs_ignoresRecipesAndBrainDump() {
        let folders = [folder("Rezepte", role: .recipes), folder("Gedanken", role: .brainDump),
                       folder("Morgens", role: .morningRoutine), folder("Abends", role: .eveningRoutine), folder("Eigener")]
        #expect(NoteFolderRules.privateFolderIDs(in: folders).isEmpty)
    }

    @Test func privateFolderIDs_coversAllPrivateRoles() {
        let folders = [folder("Tagebuch", role: .journal), folder("Bible Study", role: .bibleStudy), folder("Dream Log", role: .dreamLog)]
        #expect(NoteFolderRules.privateFolderIDs(in: folders) == Set(folders.map(\.id)))
    }

    @Test func privateFolderIDs_cycleTerminates() {
        let idA = UUID(), idB = UUID()
        let a = NoteFolderInfo(id: idA, name: "A", parentID: idB, role: .journal)
        let b = NoteFolderInfo(id: idB, name: "B", parentID: idA)
        let other = folder("Frei")
        #expect(NoteFolderRules.privateFolderIDs(in: [a, b, other]) == [idA, idB])
    }

    @Test func mayLeaveDevice_freeNoteInJournalFolder_isFalse() {
        let journal = folder("Tagebuch", role: .journal)
        let ids = NoteFolderRules.privateFolderIDs(in: [journal])
        #expect(!NoteFolderRules.mayLeaveDevice(kind: .free, folderID: journal.id, privateFolderIDs: ids))
        #expect(NoteFolderRules.mayLeaveDevice(kind: .free, folderID: nil, privateFolderIDs: ids))
        #expect(NoteFolderRules.mayLeaveDevice(kind: .morning, folderID: UUID(), privateFolderIDs: ids))
    }

    @Test func mayLeaveDevice_dreamKind_isFalse() {
        #expect(!NoteFolderRules.mayLeaveDevice(kind: .dream, folderID: nil, privateFolderIDs: []))
        #expect(!NoteFolderRules.mayLeaveDevice(kind: .journal, folderID: nil, privateFolderIDs: []))
        #expect(!NoteFolderRules.mayLeaveDevice(kind: .bibleStudy, folderID: nil, privateFolderIDs: []))
    }

    @Test func subfolderBelowSystemFolder_cannotBeCreatedOrMovedThere() throws {
        let journal = folder("Tagebuch", role: .journal)
        let own = folder("Eigener")
        #expect(!NoteFolderRules.canCreateFolder(under: journal.id, in: [journal, own]))
        #expect(throws: NoteFolderRules.MoveError.systemFolder) {
            try NoteFolderRules.validateMove(own.id, to: journal.id, in: [journal, own])
        }
    }

    @Test func canCreateFolder_belowBrainDump_isFalse() {
        let brainDump = folder("Brain Dump", role: .brainDump)
        #expect(!NoteFolderRules.canCreateFolder(under: brainDump.id, in: [brainDump]))
    }

    @Test func validateMove_brainDump_throwsSystemFolder() {
        let brainDump = folder("Brain Dump", role: .brainDump)
        let other = folder("Anderer")
        #expect(throws: NoteFolderRules.MoveError.systemFolder) { try NoteFolderRules.validateMove(brainDump.id, to: other.id, in: [brainDump, other]) }
        #expect(throws: NoteFolderRules.MoveError.systemFolder) { try NoteFolderRules.validateMove(other.id, to: brainDump.id, in: [brainDump, other]) }
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

    @Test func sortOrder_reversedKeepsPinnedOnTop() {
        let old = instant(2026, 1, 1)
        let mid = instant(2026, 6, 1)
        let new = instant(2026, 11, 1)
        let apple = NoteSortKey(isPinned: false, createdAt: new, updatedAt: old, title: "Apfel")
        let banana = NoteSortKey(isPinned: false, createdAt: old, updatedAt: new, title: "banane")
        let cherry = NoteSortKey(isPinned: true, createdAt: mid, updatedAt: mid, title: "Zitrone")
        let lemon = NoteSortKey(isPinned: true, createdAt: new, updatedAt: new, title: "Limone")
        func sorted(_ order: NoteSortOrder, reversed: Bool) -> [String] {
            [apple, banana, cherry, lemon].sorted { order.precedes($0, $1, reversed: reversed) }.map(\.title)
        }
        #expect(sorted(.modified, reversed: false) == ["Limone", "Zitrone", "banane", "Apfel"])
        #expect(sorted(.modified, reversed: true) == ["Zitrone", "Limone", "Apfel", "banane"])
        // "Z bis A" for titles.
        #expect(sorted(.title, reversed: false) == ["Limone", "Zitrone", "Apfel", "banane"])
        #expect(sorted(.title, reversed: true) == ["Zitrone", "Limone", "banane", "Apfel"])
    }

    @Test func sortOrder_groupingDateFollowsTheOrder() {
        let created = instant(2026, 1, 1)
        let updated = instant(2026, 11, 1)
        let key = NoteSortKey(isPinned: false, createdAt: created, updatedAt: updated, title: "A")
        #expect(NoteSortOrder.modified.groupingDate(of: key) == updated)
        #expect(NoteSortOrder.created.groupingDate(of: key) == created)
        #expect(NoteSortOrder.title.groupingDate(of: key) == nil)
    }
}
