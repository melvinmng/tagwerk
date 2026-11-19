import SwiftUI
import TagwerkCore

/// "Bible Study starten": pick the book (the one read last is suggested) and type the passage. The note of the book opens
/// with a new dated section below "Notizen".
struct BibleStudyStartSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let store: NoteStore
    let onStarted: (UUID) -> Void

    @State private var bookKey = "1"
    @State private var passage = ""
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Buch", selection: $bookKey) {
                        Section("Altes Testament") {
                            ForEach(BibleBooks.all.filter(\.isOldTestament)) { Text($0.name(locale: .current)).tag($0.key) }
                        }
                        Section("Neues Testament") {
                            ForEach(BibleBooks.all.filter { !$0.isOldTestament }) { Text($0.name(locale: .current)).tag($0.key) }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    TextField("Stelle, z. B. 3,21-31", text: $passage)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Der Text deiner Notizen bleibt auf deinem iPhone und geht nie an ChatGPT.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Bible Study starten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Starten", action: start) }
            }
            .onAppear {
                guard !isLoaded else { return }
                isLoaded = true
                if let last = store.lastBookKey { bookKey = last }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func start() {
        guard let book = BibleBooks.book(key: bookKey) else { return }
        let day = RoutineSchedule.routineDay(at: .now, calendar: environment.planning.calendar)
        let started = store.startSession(book: book, passage: passage, dayKey: NoteDayKey.string(day),
                                         dateText: Self.dateText(day))
        dismiss()
        onStarted(started.note.id)
    }

    /// "19.11.2026", fixed so the section titles of a note read alike whatever the language was when they were written.
    static func dateText(_ day: PlanDay) -> String {
        String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
    }
}
