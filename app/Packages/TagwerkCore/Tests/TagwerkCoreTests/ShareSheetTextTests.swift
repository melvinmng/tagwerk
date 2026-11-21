import Foundation
import Testing
@testable import TagwerkCore

struct ShareSheetTextTests {
    @Test func hints_recipe_announcesTheChoiceInTheApp() {
        let hints = ShareSheetText.hints(target: .recipe, hasFiles: false, hasText: true, hasURL: true)
        #expect(hints == [.recipeChoiceLater])
        // Files are taken over for recipes, so no drop notice appears.
        #expect(ShareSheetText.hints(target: .recipe, hasFiles: true, hasText: false, hasURL: false) == [.recipeChoiceLater])
    }

    @Test func hints_taskWithFiles_saysFilesAreDropped() {
        let hints = ShareSheetText.hints(target: .task, hasFiles: true, hasText: true, hasURL: false)
        #expect(hints == [.textAndLink, .filesDropped])
        #expect(ShareSheetText.hints(target: .task, hasFiles: true, hasText: false, hasURL: false) == [.filesDropped])
    }

    @Test func hints_taskWithoutFiles_saysTextAndLinkGoAlong() {
        #expect(ShareSheetText.hints(target: .task, hasFiles: false, hasText: false, hasURL: true) == [.textAndLink])
        #expect(ShareSheetText.hints(target: .task, hasFiles: false, hasText: true, hasURL: false) == [.textAndLink])
        #expect(ShareSheetText.hints(target: .task, hasFiles: false, hasText: false, hasURL: false).isEmpty)
    }

    @Test func hints_noteWithFiles_hasNoDropNotice() {
        let hints = ShareSheetText.hints(target: .note, hasFiles: true, hasText: true, hasURL: true)
        #expect(!hints.contains(.filesDropped))
        #expect(hints == [.textAndLink])
        #expect(ShareSheetText.hints(target: .note, hasFiles: true, hasText: false, hasURL: false).isEmpty)
    }

    @Test func hints_shopping_saysLinesBecomeItems() {
        #expect(ShareSheetText.hints(target: .shopping, hasFiles: false, hasText: true, hasURL: false) == [.linesBecomeItems])
        #expect(ShareSheetText.hints(target: .shopping, hasFiles: true, hasText: true, hasURL: false) == [.linesBecomeItems, .filesDropped])
    }

    @Test func hints_mail_saysTheAppContinues() {
        #expect(ShareSheetText.hints(target: .mailTask, hasFiles: false, hasText: true, hasURL: false) == [.mailContinuesInApp])
        // The shared file is the mail itself; it is not "dropped".
        #expect(ShareSheetText.hints(target: .mailTask, hasFiles: true, hasText: false, hasURL: false) == [.mailContinuesInApp])
    }

    @Test func symbol_isDistinctPerTarget() {
        let symbols = ShareTarget.allCases.map(ShareSheetText.symbol(for:))
        #expect(Set(symbols).count == ShareTarget.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(ShareSheetText.symbol(for: .task) == "checklist")
        #expect(ShareSheetText.symbol(for: .mailTask) == "envelope")
    }
}
