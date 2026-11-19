import SwiftUI
import TagwerkCore

/// The morning start (mockup GA1, design §7.4): up to three things to be grateful for and the day in numbers. Everything
/// is optional. "Fertig" saves and marks the start as done; swiping the sheet away saves the input without completing.
struct MorningSheet: View {
    let model: RoutinesModel
    let day: PlanDay

    init(model: RoutinesModel, day: PlanDay, notes: NoteStore, isSignedIn: @escaping () -> Bool) {
        self.model = model
        self.day = day
        _note = State(initialValue: NoteFieldModel(store: notes, kind: .morning, day: day, isSignedIn: isSignedIn))
    }
    @State private var gratitude: [String] = ["", "", ""]
    @State private var overview: RoutinesModel.Overview?
    @State private var isLoaded = false
    @State private var showsAll = false
    @State private var note: NoteFieldModel

    /// The first field, then one more each time the previous one is filled (at most three).
    private var visibleFields: Int {
        let filled = gratitude.prefix(RoutineDayValue.maximumGratitude).lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return min(RoutineDayValue.maximumGratitude, (filled ?? -1) + 2)
    }

    /// Today's open tasks, the chosen ones first, then the pre-sorted rest (rule 12).
    private var focusRows: [TaskItem] {
        let candidates = model.todayTasks()
        let marked = candidates.filter { model.isFocus($0.id) }
        return marked + candidates.filter { !model.isFocus($0.id) }
    }

    @ViewBuilder
    private var focusSection: some View {
        let marks = model.focusMarks(day)
        if day == model.today {
            let rows = focusRows
            let shown = showsAll ? rows : Array(rows.prefix(FocusRules.maximumMarks))
            Section {
                if rows.isEmpty { Text("Heute ist noch keine Aufgabe geplant.").foregroundStyle(.secondary) }
                ForEach(shown) { task in
                    Button { model.toggleFocus(task) } label: {
                        HStack {
                            Text(task.title).lineLimit(2)
                            Spacer()
                            Image(systemName: model.isFocus(task.id) ? "star.fill" : "star")
                                .foregroundStyle(model.isFocus(task.id) ? Color.yellow : Color.secondary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityValue(model.isFocus(task.id) ? String(localized: "Fokus") : "")
                }
                if rows.count > FocusRules.maximumMarks, !showsAll {
                    Button("Alle \(rows.count) Aufgaben von heute zeigen") { showsAll = true }
                }
            } header: {
                Text("Tagesfokus · \(marks.count) von \(FocusRules.maximumMarks) gewählt")
            }
        } else if !marks.isEmpty {
            // Past days: the focus can be read, not changed.
            Section("Tagesfokus") {
                ForEach(marks) { mark in
                    Label(mark.title, systemImage: mark.doneAt == nil ? "star" : "star.fill")
                        .strikethrough(mark.doneAt != nil)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dankbar für") {
                    ForEach(0..<visibleFields, id: \.self) { index in
                        TextField("Dankbar für", text: $gratitude[index])
                    }
                }
                focusSection
                if let overview {
                    Section("Heute") { Text(RoutinesModel.overviewText(overview)) }
                }
                NoteField(model: note)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tagesstart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        note.flush()
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
