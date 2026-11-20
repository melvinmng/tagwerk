import Foundation

/// Limits for the photos of one recipe import (issue 231): a recipe can be spread over several screenshots or book pages, and
/// all of them go to ChatGPT in one request. Pure rules, so they are tested in the package.
public enum RecipePhotos {
    /// At most this many photos make one recipe.
    public static let maximumCount = 6
    /// The size of all photos together after scaling (JPEG bytes); a single photo is about 100 to 300 KB at 1,024 px.
    public static let maximumTotalBytes = 6 * 1024 * 1024

    /// How many more photos fit next to `current` ones.
    public static func remainingSlots(current: Int) -> Int {
        max(0, maximumCount - max(0, current))
    }

    /// How many of `incoming` new photos are taken when `current` are there already; the first ones, in order.
    public static func accepted(current: Int, incoming: Int) -> Int {
        min(max(0, incoming), remainingSlots(current: current))
    }

    /// Whether a set of scaled photos may be sent: between one and `maximumCount` photos, none empty, within the total size.
    public static func isSendable(byteCounts: [Int]) -> Bool {
        guard (1...maximumCount).contains(byteCounts.count), byteCounts.allSatisfy({ $0 > 0 }) else { return false }
        return byteCounts.reduce(0, +) <= maximumTotalBytes
    }
}
