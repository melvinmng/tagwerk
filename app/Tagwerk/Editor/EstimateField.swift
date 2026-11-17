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
                    stepButton("minus", direction: -1, label: "Weniger")
                        .disabled(input.minutes == nil)
                    TextField("–", text: Binding(get: { input.text }, set: { input.typed($0) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($isTyping)
                        .frame(minWidth: 44, maxWidth: 64)
                        .accessibilityLabel("Geschätzter Aufwand in Stunden")
                    Text("h").foregroundStyle(.secondary)
                    stepButton("plus", direction: 1, label: "Mehr")
                }
                .padding(.horizontal, 4)
                .background(.quaternary, in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickButton(title: "Kein", spoken: "Kein Aufwand", value: nil)
                    ForEach(EstimateHours.quickValues, id: \.self) { hours in
                        quickButton(title: EstimateHours.text(minutes: Int(hours * 60)),
                                    spoken: hours == 1 ? "1 Stunde" : "\(EstimateHours.number(Int(hours * 60))) Stunden",
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
        .toolbar {
            if isTyping {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { isTyping = false }
                }
            }
        }
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

    private func quickButton(title: String, spoken: String, value: Int?) -> some View {
        Button(title) { input.choose(value) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(input.minutes == value ? .accentColor : .secondary)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(input.minutes == value ? .isSelected : [])
    }
}
