import SwiftUI
import TagwerkCore

/// What a day page shows besides its `DayPlan` and that depends on the day: the deadline card, the keyword and
/// merge suggestions, the preparation sums, the deadline marks of its events and the open AI suggestions.
///
/// The model keeps this state for the shown day in its own properties. The neighbour pages carry it in a value
/// like this one, so a preview shows the same cards as the page that follows and the model can adopt it at once
/// when the page changes.
struct DayPageExtras {
    var upcomingDeadlines: [ImportantDeadline] = []
    var deadlineSuggestions: [CalendarEvent] = []
    var preparation: [String: PreparationSummary] = [:]
    var mergeSuggestions: [MergeSuggestion] = []
    var deadlineEventIDs: Set<String> = []
    var preparationTargets: [String: PreparationTarget] = [:]
    var suggestionBatches: [SuggestionBatch] = []
    /// Blocks that were cut when their task was completed, by event ID (FO15b).
    var trimmedBlocks: [String: TrimmedBlock] = [:]
}

/// A time block that ended early: how long it was planned and how long it ran (FO15b).
struct TrimmedBlock: Equatable {
    let plannedMinutes: Int
    let actualMinutes: Int
}

private struct DayPageExtrasKey: EnvironmentKey {
    static let defaultValue: DayPageExtras? = nil
}

private struct IsPagePreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set on the preview of a neighbour page: its views read this state instead of the model's.
    var dayPageExtras: DayPageExtras? {
        get { self[DayPageExtrasKey.self] }
        set { self[DayPageExtrasKey.self] = newValue }
    }

    /// The view is the preview of a neighbour page: no scrolling to the current time, no interaction.
    var isPagePreview: Bool {
        get { self[IsPagePreviewKey.self] }
        set { self[IsPagePreviewKey.self] = newValue }
    }
}

/// The vertical scroll offset of the shown page, written by the page and read when a drag starts, so the previews
/// of the neighbour pages stand at the same height. Not observable: it changes with every scroll frame.
@MainActor
final class ScrollOffsetBox {
    var y: CGFloat = 0
}
