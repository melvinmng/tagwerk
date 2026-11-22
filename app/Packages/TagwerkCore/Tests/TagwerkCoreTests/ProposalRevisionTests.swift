import Testing
@testable import TagwerkCore

/// The rules for editing AI proposals by hand and revising them with a follow-up message
/// (plan ki-vorschlaege-anpassen, task A3).
struct ProposalRevisionTests {
    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        var value: String
    }

    private func revision(_ values: [(String, String)] = [("a", "Mehl"), ("b", "Zucker"), ("c", "Eier")]) -> ProposalRevision<Row> {
        ProposalRevision(items: values.map { Row(id: $0.0, value: $0.1) })
    }

    // MARK: Scope one

    @Test func scopeOne_keepsEverythingButTheNamedItem() {
        var revision = revision()
        let outcome = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl"), Row(id: "b", value: "Rohrzucker")], scope: .one("a"))

        #expect(revision.items.map(\.value) == ["Dinkelmehl", "Zucker", "Eier"])
        #expect(outcome.changed == ["a"])
        #expect(outcome.ignored == ["b"])
        #expect(revision.mark(of: "a") == .byAssistant)
        #expect(revision.mark(of: "b") == nil)
    }

    @Test func scopeOne_changesTheNamedItemEvenWhenTheUserSetIt() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))

        let outcome = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl")], scope: .one("a"))

        #expect(revision.items.first?.value == "Dinkelmehl")
        #expect(revision.mark(of: "a") == .byAssistant)
        // The user asked about this item, so nothing was overwritten behind their back.
        #expect(outcome.overwritten.isEmpty)
    }

    @Test func scopeOne_keepsPinnedItemsAndIgnoresUnknownIDs() {
        var revision = revision()
        revision.edit(Row(id: "b", value: "Honig"))

        let outcome = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl"), Row(id: "b", value: "Zucker"), Row(id: "x", value: "Neu")],
                                     scope: .one("a"))

        #expect(revision.items.map(\.value) == ["Dinkelmehl", "Honig", "Eier"])
        #expect(Set(outcome.ignored) == ["b", "x"])
    }

    // MARK: Screen copy

    @Test func syncByHand_marksEditedAndAddedItemsAndDropsRemovedOnes() {
        var revision = revision()

        revision.syncByHand([Row(id: "a", value: "Roggenmehl"), Row(id: "c", value: "Eier"), Row(id: "d", value: "Butter")])

        #expect(revision.items.map(\.id) == ["a", "c", "d"])
        #expect(revision.mark(of: "a") == .byUser && revision.mark(of: "d") == .byUser && revision.mark(of: "c") == nil)
        #expect(revision.proposal(of: "a")?.value == "Mehl")
        #expect(revision.pinnedIDs == ["a", "d"])
    }

    @Test func syncByHand_dropsTheUndoStep_andIgnoresAnUnchangedList() {
        var revision = revision()
        revision.replaceAll(with: [Row(id: "a", value: "Dinkelmehl"), Row(id: "b", value: "Zucker"), Row(id: "c", value: "Eier")])
        revision.syncByHand(revision.items)
        #expect(revision.canUndo)
        revision.syncByHand([Row(id: "a", value: "Dinkelmehl"), Row(id: "c", value: "Eier")])
        #expect(!revision.canUndo)
    }

    // MARK: Replacing everything

    @Test func replaceAll_addsChangesAndRemovesItems() {
        var revision = revision()
        revision.edit(Row(id: "b", value: "Honig"))

        let outcome = revision.replaceAll(with: [Row(id: "a", value: "Mehl"), Row(id: "c", value: "Eigelb"), Row(id: "d", value: "Butter")])

        #expect(revision.items.map(\.value) == ["Mehl", "Eigelb", "Butter"])
        #expect(outcome.changed == ["c"] && outcome.added == ["d"] && outcome.removed == ["b"])
        // "b" was set by hand and the answer dropped it: reported, and "Rückgängig" brings it back with its mark.
        #expect(outcome.overwritten == ["b"])
        #expect(revision.mark(of: "c") == .byAssistant && revision.mark(of: "d") == .byAssistant && revision.mark(of: "a") == nil)
        let undone = revision.undo()
        #expect(undone)
        #expect(revision.items.map(\.value) == ["Mehl", "Honig", "Eier"] && revision.mark(of: "b") == .byUser)
    }

    @Test func replaceAll_reportsPinnedItemsTheAnswerChanges() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))

        let outcome = revision.replaceAll(with: [Row(id: "a", value: "Dinkelmehl"), Row(id: "b", value: "Zucker"), Row(id: "c", value: "Eier")])

        #expect(outcome.overwritten == ["a"] && outcome.changed == ["a"])
        #expect(revision.mark(of: "a") == .byAssistant && revision.proposal(of: "a") == nil)
    }

    @Test func replaceAll_keepsMarksOfRepeatedItemsAndIsNoStepWhenNothingChanged() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))

        let outcome = revision.replaceAll(with: revision.items)

        #expect(outcome == ProposalRevision<Row>.Outcome())
        #expect(revision.mark(of: "a") == .byUser && !revision.canUndo)
    }

    @Test func replaceAll_ignoresRepeatedIDsAndFollowsTheAnswerOrder() {
        var revision = revision()
        let outcome = revision.replaceAll(with: [Row(id: "c", value: "Eier"), Row(id: "a", value: "Mehl"), Row(id: "a", value: "Zweimal"),
                                                 Row(id: "b", value: "Zucker")])
        #expect(revision.items.map(\.id) == ["c", "a", "b"] && outcome.ignored == ["a"])
        #expect(revision.canUndo)
    }

    // MARK: Scope all

    @Test func scopeAll_changesNamedItemsAndLeavesTheRest() {
        var revision = revision()

        let outcome = revision.apply(answer: [Row(id: "c", value: "Eigelb")], scope: .all)

        #expect(revision.items.map(\.value) == ["Mehl", "Zucker", "Eigelb"])
        #expect(outcome.changed == ["c"])
        #expect(outcome.overwritten.isEmpty)
    }

    @Test func scopeAll_marksOverwrittenUserChanges() {
        var revision = revision()
        revision.edit(Row(id: "b", value: "Honig"))

        let outcome = revision.apply(answer: [Row(id: "b", value: "Ahornsirup"), Row(id: "c", value: "Eigelb")], scope: .all)

        #expect(outcome.changed == ["b", "c"])
        // The user set "b" by hand; the answer changed it anyway, which has to be visible.
        #expect(outcome.overwritten == ["b"])
        #expect(revision.mark(of: "b") == .byAssistant)
        #expect(revision.mark(of: "c") == .byAssistant)
    }

    @Test func scopeAll_aPinnedItemTheAnswerRepeatsStaysPinned() {
        var revision = revision()
        revision.edit(Row(id: "b", value: "Honig"))

        let outcome = revision.apply(answer: [Row(id: "b", value: "Honig")], scope: .all)

        #expect(outcome.changed.isEmpty)
        #expect(outcome.overwritten.isEmpty)
        #expect(revision.mark(of: "b") == .byUser)
    }

    @Test func answerThatChangesNothing_leavesNoUndo() {
        var revision = revision()
        let outcome = revision.apply(answer: [Row(id: "a", value: "Mehl")], scope: .all)

        #expect(outcome.changed.isEmpty)
        #expect(!revision.canUndo)
    }

    // MARK: Pinned

    @Test func pinned_listedInRequest() {
        var revision = revision()
        #expect(revision.pinnedIDs.isEmpty)
        revision.edit(Row(id: "c", value: "Eigelb"))
        revision.edit(Row(id: "a", value: "Roggenmehl"))

        // In the order of the items, not of the edits.
        #expect(revision.pinnedIDs == ["a", "c"])
        _ = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl")], scope: .one("a"))
        #expect(revision.pinnedIDs == ["c"])
    }

    // MARK: Manual edits

    @Test func edit_setsTheUserMarkAndKeepsTheProposalOfTheAI() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))

        #expect(revision.items.first?.value == "Roggenmehl")
        #expect(revision.mark(of: "a") == .byUser)
        #expect(revision.proposal(of: "a")?.value == "Mehl")
        // A second edit does not replace what the AI proposed.
        revision.edit(Row(id: "a", value: "Dinkelmehl"))
        #expect(revision.proposal(of: "a")?.value == "Mehl")
    }

    @Test func edit_unknownIDOrSameValue_changesNothing() {
        var revision = revision()
        revision.edit(Row(id: "x", value: "Neu"))
        revision.edit(Row(id: "a", value: "Mehl"))

        #expect(revision.items == self.revision().items)
        #expect(revision.mark(of: "a") == nil)
    }

    @Test func resetToProposal_restoresTheValueAndDropsTheMark() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))

        revision.resetToProposal("a")

        #expect(revision.items.first?.value == "Mehl")
        #expect(revision.mark(of: "a") == nil)
        #expect(revision.proposal(of: "a") == nil)
        #expect(revision.pinnedIDs.isEmpty)
    }

    @Test func editBackToTheProposal_dropsTheMark() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))
        revision.edit(Row(id: "a", value: "Mehl"))

        #expect(revision.mark(of: "a") == nil)
    }

    @Test func answerForAnEditedItem_becomesTheNewProposalOfTheAI() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))
        _ = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl")], scope: .one("a"))

        // "Back to the proposal" now means back to what the AI said last.
        #expect(revision.proposal(of: "a") == nil)
        #expect(revision.mark(of: "a") == .byAssistant)
    }

    // MARK: Undo

    @Test func undo_restoresStateBeforeAnswer() {
        var revision = revision()
        revision.edit(Row(id: "a", value: "Roggenmehl"))
        let before = revision
        _ = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl"), Row(id: "c", value: "Eigelb")], scope: .all)
        #expect(revision.canUndo)

        let undone = revision.undo()

        #expect(undone)
        #expect(revision.items == before.items)
        #expect(revision.mark(of: "a") == .byUser)
        #expect(revision.mark(of: "c") == nil)
        #expect(revision.proposal(of: "a")?.value == "Mehl")
        // One step only.
        #expect(!revision.canUndo)
        let again = revision.undo()
        #expect(!again)
    }

    @Test func undo_clearedByManualEdit() {
        var revision = revision()
        _ = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl")], scope: .all)
        #expect(revision.canUndo)

        revision.edit(Row(id: "b", value: "Honig"))

        // Undoing the answer would also undo the edit (like moving a suggestion in "Tag planen").
        #expect(!revision.canUndo)
    }

    @Test func secondAnswer_replacesTheUndoStep() {
        var revision = revision()
        _ = revision.apply(answer: [Row(id: "a", value: "Dinkelmehl")], scope: .all)
        _ = revision.apply(answer: [Row(id: "c", value: "Eigelb")], scope: .all)

        _ = revision.undo()

        #expect(revision.items.map(\.value) == ["Dinkelmehl", "Zucker", "Eier"])
    }
}

struct FollowUpAvailabilityTests {
    @Test func followUpBar_hiddenWithoutConsentOrSignIn() {
        #expect(FollowUpAvailability.state(hasConsent: false, isSignedIn: true, isOffline: false) == .hidden)
        #expect(FollowUpAvailability.state(hasConsent: true, isSignedIn: false, isOffline: false) == .hidden)
        #expect(FollowUpAvailability.state(hasConsent: false, isSignedIn: false, isOffline: true) == .hidden)
    }

    @Test func followUpBar_disabledOffline_manualEditStillWorks() {
        // The bar stays visible but cannot send; editing by hand does not depend on this state.
        #expect(FollowUpAvailability.state(hasConsent: true, isSignedIn: true, isOffline: true) == .offline)
        var revision = ProposalRevision(items: [ProposalRevisionTests.Row(id: "a", value: "Mehl")])
        revision.edit(.init(id: "a", value: "Roggenmehl"))
        #expect(revision.mark(of: "a") == .byUser)
    }

    @Test func followUpBar_availableWithConsentSignInAndNetwork() {
        #expect(FollowUpAvailability.state(hasConsent: true, isSignedIn: true, isOffline: false) == .available)
    }

    @Test func canSend_needsAnAvailableBarAndTextWithoutRunningRequest() {
        #expect(FollowUpAvailability.canSend(.available, text: " Ohne Gewürze ", isSending: false))
        #expect(!FollowUpAvailability.canSend(.available, text: "  ", isSending: false))
        #expect(!FollowUpAvailability.canSend(.available, text: "Ohne Gewürze", isSending: true))
        #expect(!FollowUpAvailability.canSend(.offline, text: "Ohne Gewürze", isSending: false))
        #expect(!FollowUpAvailability.canSend(.hidden, text: "Ohne Gewürze", isSending: false))
    }
}
