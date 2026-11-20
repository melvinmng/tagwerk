import SwiftUI
import TagwerkCore

/// Replaces `Stepper` where a number can also be typed (#218): tapping the value opens a field, − and + keep working.
///
/// The range and the step apply to − and + and to the typed value alike. A typed value outside the range is set to the
/// limit, one between two steps is rounded to the nearest step, and a note under the row says so. Pass an accessibility
/// identifier from outside with `.accessibilityIdentifier(_:)` as for any other view.
struct ValueStepper: View {
    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let unit: LocalizedStringKey?
    private let display: (Double) -> String

    @State private var model: ValueEntryModel
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whole-number value stored as `Int`.
    /// - Parameters:
    ///   - kind: `.integer` for counts, `.durationMinutes` for minutes (also reads "1,5 h" and "1:30").
    ///   - scale: Typed unit times `scale` is the stored unit (`1000` when liters are typed and milliliters are stored).
    ///   - unit: Shown next to the field while typing.
    ///   - display: The value as the row shows it, for example "1 h 30 min".
    init(_ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         kind: NumberEntryKind = .integer, scale: Double = 1, unit: LocalizedStringKey? = nil,
         display: @escaping (Int) -> String) {
        let adapter = Binding<Double>(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) })
        self.init(title: title, value: adapter, range: Double(range.lowerBound)...Double(range.upperBound), step: Double(step),
                  kind: kind, scale: scale, unit: unit, display: { display(Int($0.rounded())) })
    }

    /// Decimal value stored as `Double`, for example the quantity factor of a meal item.
    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         kind: NumberEntryKind, scale: Double = 1, unit: LocalizedStringKey? = nil, display: @escaping (Double) -> String) {
        self.init(title: title, value: value, range: range, step: step, kind: kind, scale: scale, unit: unit, display: display)
    }

    private init(title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                 kind: NumberEntryKind, scale: Double, unit: LocalizedStringKey?, display: @escaping (Double) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.display = display
        self._model = State(initialValue: ValueEntryModel(kind: kind, range: range, step: step, scale: scale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            rowLayout {
                Text(title)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    valueView
                    stepButton("minus", direction: -1, label: "Weniger").disabled(value <= range.lowerBound)
                    stepButton("plus", direction: 1, label: "Mehr").disabled(value >= range.upperBound)
                }
            }
            if let hint = model.hint {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .modifier(StepperAccessibility(isEditing: model.isEditing, title: title, valueText: display(value),
                                       adjust: step(_:), enterValue: beginEditing))
        .onChange(of: isFocused) { _, focused in if !focused { finishEditing() } }
        .onChange(of: model.hint) { _, hint in
            if let hint { AccessibilityNotification.Announcement(hint).post() }
        }
        .task(id: model.hint) {
            // The note is short-lived: it goes away after a few seconds.
            guard model.hint != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { model.clearHint() }
        }
    }

    /// Title and controls side by side, one below the other at accessibility text sizes so nothing is cut off.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
    }

    @ViewBuilder private var valueView: some View {
        if model.isEditing {
            HStack(spacing: 4) {
                TextField("", text: Binding(get: { model.text }, set: typed(_:)))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .keyboardDoneButton(focus: $isFocused)
                    .submitLabel(.done)
                    .onSubmit { isFocused = false }
                    .frame(minWidth: 56, maxWidth: 120)
                    .onAppear { isFocused = true }
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        } else {
            Button(action: beginEditing) {
                Text(display(value)).foregroundStyle(.tint).multilineTextAlignment(.trailing)
            }
            .buttonStyle(.borderless)  // inside a Form row, default buttons all fire together
        }
    }

    private func stepButton(_ symbol: String, direction: Int, label: LocalizedStringKey) -> some View {
        Button {
            step(direction)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    /// Number pad for whole numbers; decimal pad for decimals. Durations get the punctuation keyboard
    /// so "1:30" and "1 h 30" can be typed (the decimal pad has neither a colon nor letters).
    private var keyboard: UIKeyboardType {
        switch model.kind {
        case .integer: .numberPad
        case .decimal: .decimalPad
        case .durationMinutes: .numbersAndPunctuation
        }
    }

    private func beginEditing() {
        model.begin(value: value)
    }

    private func typed(_ text: String) {
        if let live = model.typed(text), live != value { value = live }
    }

    private func finishEditing() {
        guard model.isEditing else { return }
        let committed = model.commit(current: value, display: display)
        if committed != value { value = committed }
    }

    /// One step up (`direction` 1) or down (-1), limited to the range.
    private func step(_ direction: Int) {
        finishEditing()
        let next = min(max(value + Double(direction) * step, range.lowerBound), range.upperBound)
        if next != value { value = next }
    }
}

/// While the field is open it is an ordinary accessible field. Otherwise the row is one adjustable element
/// (swipe up and down change the value by one step) with the extra action "Wert eingeben".
private struct StepperAccessibility: ViewModifier {
    let isEditing: Bool
    let title: LocalizedStringKey
    let valueText: String
    let adjust: (Int) -> Void
    let enterValue: () -> Void

    func body(content: Content) -> some View {
        if isEditing {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(1)
                    case .decrement: adjust(-1)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: Text("Wert eingeben"), enterValue)
        }
    }
}
