import Foundation
import TagwerkCore

/// State and rules of a stepper value that can also be typed (#218). Pure, so the rules are testable without a view.
///
/// Values are kept in the stored unit (for example milliliters). `scale` converts the typed unit into the stored one
/// (`1000` when liters are typed and milliliters are stored).
struct ValueEntryModel {
    let kind: NumberEntryKind
    /// Allowed values in the stored unit.
    let range: ClosedRange<Double>
    /// Step in the stored unit; typed values are rounded to it, counted from `range.lowerBound`.
    let step: Double
    let scale: Double
    let locale: Locale

    /// What the field shows while it is being edited.
    private(set) var text = ""
    private(set) var isEditing = false
    /// Short note under the row after an entry was not readable or had to be adjusted.
    private(set) var hint: String?
    private var valueAtBegin = 0.0

    init(kind: NumberEntryKind, range: ClosedRange<Double>, step: Double, scale: Double = 1, locale: Locale = .current) {
        self.kind = kind
        self.range = range
        self.step = step
        self.scale = scale
        self.locale = locale
    }

    /// Opens the field with the current value, without unit and without grouping separator.
    mutating func begin(value: Double) {
        valueAtBegin = value
        text = NumberEntry.editingText(value / scale, kind: kind, locale: locale)
        isEditing = true
        hint = nil
    }

    /// Takes the typed text. Returns the value to store right away (limited and rounded), or `nil` while the text is not
    /// readable. Storing on every keystroke means saving a sheet with the keyboard still open never loses the entry.
    mutating func typed(_ newText: String) -> Double? {
        text = newText
        guard let parsed = NumberEntry.parse(newText, kind: kind, locale: locale) else { return nil }
        return NumberEntry.normalize(parsed * scale, range: range, step: step)
    }

    /// Ends the editing and returns the value to store. An unreadable entry brings back the value from before the editing
    /// and shows a hint; an entry that had to be limited or rounded shows what it was adjusted to.
    mutating func commit(current: Double, display: (Double) -> String) -> Double {
        guard isEditing else { return current }
        isEditing = false
        guard let parsed = NumberEntry.parse(text, kind: kind, locale: locale) else {
            hint = String(localized: "Bitte eine Zahl eingeben.")
            return valueAtBegin
        }
        let raw = parsed * scale
        let normalized = NumberEntry.normalize(raw, range: range, step: step)
        if NumberEntry.wasAdjusted(raw, normalized: normalized) {
            let shown = display(normalized)
            hint = String(localized: "Angepasst auf \(shown)")
        } else {
            hint = nil
        }
        return normalized
    }

    mutating func clearHint() { hint = nil }
}
