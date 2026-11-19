import SwiftUI

/// Effort control (mockup 3A): typeable hours between − and +, quick values below.
struct EstimateField: View {
    @Binding var minutes: Int?
    @FocusState private var isTyping: Bool
    @State private var input = EstimateInput(minutes: nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Geschätzt") {
                HStack(spacing: 2) {
                    stepButton("minus", direction: -1, label: String(localized: "Weniger"))
                        .disabled(input.minutes == nil)
                    TextField("–", text: Binding(get: { input.text }, set: { input.typed($0) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($isTyping)
                        .keyboardDoneButton(focus: $isTyping)
                        .frame(minWidth: 44, maxWidth: 64)
                        .accessibilityLabel("Geschätzter Aufwand in Stunden")
                    Text("h").foregroundStyle(.secondary)
                    stepButton("plus", direction: 1, label: String(localized: "Mehr"))
                }
                .padding(.horizontal, 4)
                .background(.quaternary, in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickButton(title: String(localized: "Kein"), spoken: String(localized: "Kein Aufwand"), value: nil)
                    ForEach(EstimateHours.quickValues, id: \.self) { hours in
                        quickButton(title: EstimateHours.text(minutes: Int(hours * 60)),
                                    spoken: spokenHours(hours),
                                    value: Int(hours * 60))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { input = EstimateInput(minutes: minutes) }
        .onChange(of: input.minutes) { _, value in if minutes != value { minutes = value } }
        .onChange(of: minutes) { _, value in
            // External changes (reload after a conflict) replace the field content.
            if input.minutes != value { input = EstimateInput(minutes: value) }
        }
        .onChange(of: isTyping) { _, typing in if !typing { input.endEditing() } }
    }

    private func stepButton(_ symbol: String, direction: Int, label: String) -> some View {
        Button {
            input.step(direction)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)  // inside a Form row, default buttons all fire together
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    /// "1 Stunde", "0,5 Stunden": the plural variants of the count are in the catalog.
    private func spokenHours(_ hours: Double) -> String {
        hours == 1 ? String(localized: "1 Stunde") : String(localized: "\(EstimateHours.number(Int(hours * 60))) Stunden")
    }

    private func quickButton(title: String, spoken: String, value: Int?) -> some View {
        Button(title) { input.choose(value) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(input.minutes == value ? .accentColor : .secondary)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(input.minutes == value ? .isSelected : [])
    }
}
