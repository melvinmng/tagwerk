import SwiftUI
import TagwerkCore

/// "Bible Study starten" (BS2b, BV1b): the books read last as chips, the start and end of the passage on wheels, and the
/// button that repeats the passage. The note of the book opens with a new dated section below "Notizen".
struct BibleStudyStartSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let store: NoteStore
    let onStarted: (UUID) -> Void

    @State private var model: BibleStudyStartModel?

    private enum Wheel { case from, to }
    @State private var openWheel: Wheel?

    init(store: NoteStore, onStarted: @escaping (UUID) -> Void) {
        self.store = store
        self.onStarted = onStarted
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model { form(model) } else { Color.clear }
            }
            .navigationTitle("Bible Study starten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .onAppear {
                if model == nil { model = BibleStudyStartModel(store: store, calendar: environment.planning.calendar, locale: locale) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func form(_ model: BibleStudyStartModel) -> some View {
        Form {
            Section {
                chips(model)
                if let notice = model.finishedNotice { Text(notice).font(.footnote).foregroundStyle(.secondaryText) }
            } header: {
                Text("Buch")
            }
            Section {
                if model.usesFreeText {
                    TextField("Stelle, z. B. 3,21–31", text: Bindable(model).freeText)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                } else {
                    fromRow(model)
                    toRow(model)
                }
                Button(model.usesFreeText ? "Räder zeigen" : "Stelle frei eingeben") { model.usesFreeText.toggle() }
                    .frame(minHeight: 44, alignment: .leading)
            } header: {
                Text("Stelle")
            } footer: {
                Text("Geht nie an ChatGPT.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { start(model) } label: {
                Text(model.startTitle).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
            .accessibilityIdentifier("bibleStudy.start")
        }
    }

    // MARK: Book

    private func chips(_ model: BibleStudyStartModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.recentBooks) { book in
                    chip(book.name(locale: locale), isSelected: book == model.book) { select(book, in: model) }
                }
                NavigationLink {
                    BibleBookPicker(selected: model.book) { select($0, in: model) }
                } label: {
                    Text("Anderes …").frame(minHeight: 44).padding(.horizontal, 12)
                        .background(.quaternary, in: Capsule())
                }
                .tint(.primary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minHeight: 44).padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
        .background(.quaternary, in: Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ book: BibleBook, in model: BibleStudyStartModel) {
        model.select(book)
        openWheel = nil
    }

    // MARK: Passage

    private func fromRow(_ model: BibleStudyStartModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { openWheel = openWheel == .from ? nil : .from } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Von")
                        if let hint = model.hint { Text(hint).font(.caption).foregroundStyle(.secondaryText) }
                    }
                    Spacer()
                    Text(model.from.text).foregroundStyle(.tint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .tint(.primary)
            .accessibilityIdentifier("bibleStudy.from")
            if openWheel == .from {
                wheels(model, selection: model.from, chapters: 1...max(model.chapterCount, 1),
                       verses: { 1...max(model.verseCount(chapter: $0), 1) }) { model.setFrom(chapter: $0, verse: $1) }
            }
        }
    }

    private func toRow(_ model: BibleStudyStartModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { openWheel = openWheel == .to ? nil : .to } label: {
                HStack {
                    Text("Bis")
                    Spacer()
                    Text(model.to?.text ?? String(localized: "offen")).foregroundStyle(.tint)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(openWheel == .to ? .degrees(90) : .zero)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .tint(.primary)
            .accessibilityIdentifier("bibleStudy.to")
            if openWheel == .to {
                wheels(model, selection: model.to ?? model.from, chapters: model.from.chapter...max(model.chapterCount, model.from.chapter),
                       verses: { chapter in (chapter == model.from.chapter ? model.from.verse : 1)...max(model.verseCount(chapter: chapter), 1) }) {
                    model.setTo(chapter: $0, verse: $1)
                }
                Button("Offen lassen") { model.openEnd(); openWheel = nil }
                    .frame(minHeight: 44)
            }
        }
    }

    private func wheels(_ model: BibleStudyStartModel, selection: BibleReference, chapters: ClosedRange<Int>,
                        verses: @escaping (Int) -> ClosedRange<Int>, set: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Picker("Kapitel", selection: Binding(get: { selection.chapter }, set: { set($0, selection.verse) })) {
                ForEach(chapters, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Picker("Vers", selection: Binding(get: { selection.verse }, set: { set(selection.chapter, $0) })) {
                ForEach(verses(selection.chapter), id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
        }
        .frame(height: 120)
    }

    // MARK: Start

    private func start(_ model: BibleStudyStartModel) {
        let day = RoutineSchedule.routineDay(at: .now, calendar: environment.planning.calendar)
        let noteID = model.start(day: day)
        dismiss()
        onStarted(noteID)
    }

    /// "19.11.2026", fixed so the section titles of a note read alike whatever the language was when they were written.
    static func dateText(_ day: PlanDay) -> String {
        BibleStudyTemplate.dateText(day)
    }
}
