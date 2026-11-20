import Testing
@testable import TagwerkCore

struct RecipePhotosTests {
    @Test func accepted_takesOnlyWhatFits() {
        #expect(RecipePhotos.maximumCount == 6)
        #expect(RecipePhotos.accepted(current: 0, incoming: 3) == 3)
        #expect(RecipePhotos.accepted(current: 4, incoming: 5) == 2)
        #expect(RecipePhotos.accepted(current: 6, incoming: 1) == 0)
        #expect(RecipePhotos.accepted(current: 9, incoming: 1) == 0)
        #expect(RecipePhotos.accepted(current: 0, incoming: -2) == 0)
    }

    @Test func remainingSlots_neverNegative() {
        #expect(RecipePhotos.remainingSlots(current: 0) == 6)
        #expect(RecipePhotos.remainingSlots(current: 2) == 4)
        #expect(RecipePhotos.remainingSlots(current: 7) == 0)
    }

    @Test func isSendable_checksCountAndSize() {
        #expect(RecipePhotos.isSendable(byteCounts: [200_000]))
        #expect(RecipePhotos.isSendable(byteCounts: Array(repeating: 300_000, count: 6)))
        #expect(!RecipePhotos.isSendable(byteCounts: []))
        #expect(!RecipePhotos.isSendable(byteCounts: Array(repeating: 1, count: 7)))
        #expect(!RecipePhotos.isSendable(byteCounts: [100, 0]))
        #expect(!RecipePhotos.isSendable(byteCounts: [RecipePhotos.maximumTotalBytes, 1]))
        #expect(RecipePhotos.isSendable(byteCounts: [RecipePhotos.maximumTotalBytes]))
    }
}
