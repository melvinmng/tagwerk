import Foundation

/// One line of the folder "Tagesstart": a note of a day, or a day that only has gratitude and no note (design NO14).
public enum RoutineFolderEntry<NoteID: Hashable & Sendable>: Sendable, Hashable {
    case note(id: NoteID, day: PlanDay?)
    case gratitudeOnly(day: PlanDay)
}

public enum RoutineFolderEntries {
    /// The entries of the folder, days descending. A day that has a live note is listed once, as its note; a day
    /// without a live note that has gratitude is listed as `.gratitudeOnly`.
    ///
    /// The caller passes only live notes. That is what keeps a day in the list after its note was deleted: the note
    /// lies in "Zuletzt gelöscht" for 30 days like every other note, and as long as gratitude is entered for the day,
    /// the day stays listed as an entry without a note. The gratitude is cleared in the morning routine only.
    /// Notes without a day come last in the order they came in; notes of the same day keep their order.
    public static func merge<NoteID>(notes: [(id: NoteID, day: PlanDay?)],
                                     gratitudeDays: Set<PlanDay>) -> [RoutineFolderEntry<NoteID>] {
        let noteDays = Set(notes.compactMap { $0.day })
        var entries: [(entry: RoutineFolderEntry<NoteID>, day: PlanDay?)] = notes.map { (.note(id: $0.id, day: $0.day), $0.day) }
        for day in gratitudeDays.subtracting(noteDays) { entries.append((.gratitudeOnly(day: day), day)) }
        // Stable: equal days and the notes without a day keep the order they came in.
        let indexed = entries.enumerated().sorted { first, second in
            switch (first.element.day, second.element.day) {
            case let (a?, b?): return a != b ? a > b : first.offset < second.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return first.offset < second.offset
            }
        }
        return indexed.map { $0.element.entry }
    }

    /// Notes plus the days with gratitude only, for the count in the folder overview.
    public static func count(noteDays: [PlanDay?], gratitudeDays: Set<PlanDay>) -> Int {
        noteDays.count + gratitudeDays.subtracting(noteDays.compactMap { $0 }).count
    }
}
