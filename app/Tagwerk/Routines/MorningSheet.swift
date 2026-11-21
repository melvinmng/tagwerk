import SwiftUI
import TagwerkCore

/// The morning start (design §7.4): a gentle start with the brain dump, up to three things to be grateful for and an
/// optional dream log. Planning is not part of it; "Planen" covers that. Everything is optional. "Abschließen" saves and marks
/// the start as done; swiping the sheet away saves the input without completing.
struct MorningSheet: View {
    let model: RoutinesModel
    let day: PlanDay

    init(model: RoutinesModel, day: PlanDay, notes: NoteStore, isSignedIn: @escaping () -> Bool) {
        self.model = model
        self.day = day
        _note = State(initialValue: NoteFieldModel(store: notes, kind: .morning, day: day, isSignedIn: isSignedIn))
        // The dream log is never sent anywhere, so it gets no sign-in check to begin with.
        _dream = State(initialValue: NoteFieldModel(store: notes, kind: .dream, day: day))
    }
    @State private var gratitude: [String] = ["", "", ""]
    @State private var isLoaded = false
    @State private var note: NoteFieldModel
    @State private var dream: NoteFieldModel

    /// The first field, then one more each time the previous one is filled (at most three).
    private var visibleFields: Int {
        let filled = gratitude.prefix(RoutineDayValue.maximumGratitude).lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return min(RoutineDayValue.maximumGratitude, (filled ?? -1) + 2)
    }

    var body: some View {
        NavigationStack {
            Form {
                NoteField(model: note)
                Section("Dankbar für") {
                    ForEach(0..<visibleFields, id: \.self) { index in
                        TextField("Dankbar für", text: $gratitude[index])
                    }
                }
                NoteField(model: dream)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tagesstart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Abschließen") {
                        note.flush()
                        dream.flush()
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
            }
            // Swiping the sheet away: what was typed stays, the start is not marked as done.
            .onDisappear { if isLoaded { model.setGratitude(gratitude, on: day) } }
        }
    }
}
