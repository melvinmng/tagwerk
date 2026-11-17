import SwiftUI

/// Effort control (mockup 3A): typeable hours between − and +, quick values below.
struct EstimateField: View {
    @Binding var minutes: Int?
    @FocusState private var isTyping: Bool
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Geschätzt") {
                HStack(spacing: 2) {
                    stepButton("minus", direction: -1, label: "Weniger")
                        .disabled(minutes == nil)
                    TextField("–", text: $text)
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
                    quickButton(title: "Kein", value: nil)
                    ForEach(EstimateHours.quickValues, id: \.self) { hours in
                        quickButton(title: EstimateHours.text(minutes: Int(hours * 60)), value: Int(hours * 60))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { text = currentText }
        .onChange(of: minutes) { _, _ in if !isTyping { text = currentText } }
        .onChange(of: isTyping) { _, typing in
            // Commit on leaving the field: round to a quarter hour within 0,25–24 h.
            if !typing { commitTypedValue() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { isTyping = false }
            }
        }
    }

    private var currentText: String {
        minutes.map(EstimateHours.number) ?? ""
    }

    private func commitTypedValue() {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        minutes = EstimateHours.minutes(fromHours: Double(normalized))
        text = currentText
    }

    private func stepButton(_ symbol: String, direction: Int, label: String) -> some View {
        Button {
            if isTyping { commitTypedValue() }
            minutes = EstimateHours.stepped(minutes: minutes, by: direction)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)  // inside a Form row, default buttons all fire together
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func quickButton(title: String, value: Int?) -> some View {
        Button(title) {
            isTyping = false
            minutes = value
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(minutes == value ? .accentColor : .secondary)
        .accessibilityAddTraits(minutes == value ? .isSelected : [])
    }
}
