import SwiftUI
import TagwerkCore

/// The morning start (mockup GA1, design §7.4): up to three things to be grateful for and the day in numbers. Everything
/// is optional. "Fertig" saves and marks the start as done; swiping the sheet away saves the input without completing.
struct MorningSheet: View {
    let model: RoutinesModel
    let day: PlanDay
    @State private var gratitude: [String] = ["", "", ""]
    @State private var overview: RoutinesModel.Overview?
    @State private var isLoaded = false

    /// The first field, then one more each time the previous one is filled (at most three).
    private var visibleFields: Int {
        let filled = gratitude.prefix(RoutineDayValue.maximumGratitude).lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return min(RoutineDayValue.maximumGratitude, (filled ?? -1) + 2)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dankbar für") {
                    ForEach(0..<visibleFields, id: \.self) { index in
                        TextField("Dankbar für", text: $gratitude[index])
                    }
                }
                if let overview {
                    Section("Heute") { Text(RoutinesModel.overviewText(overview)) }
                }
            }
            .navigationTitle("Tagesstart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        model.setGratitude(gratitude, on: day)
                        model.finishStart(day)
                    }
                }
            }
            .task {
                if !isLoaded {
                    isLoaded = true
                    let stored = model.value(day).gratitude
                    gratitude = stored + Array(repeating: "", count: max(0, RoutineDayValue.maximumGratitude - stored.count))
                }
                overview = await model.overview(for: day)
            }
            // Swiping the sheet away: what was typed stays, the start is not marked as done.
            .onDisappear { if isLoaded { model.setGratitude(gratitude, on: day) } }
        }
    }
}
