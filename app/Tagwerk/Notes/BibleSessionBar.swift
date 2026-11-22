import SwiftUI
import TagwerkCore

/// The running session above the text of a Bible Study note (BS1b): "Sitzung läuft · Römer ab 3,21" with "Abschließen". A tap
/// opens "Bis wohin gelesen?" with two wheels; confirming completes the session, the bar turns green for two seconds
/// ("Sitzung abgeschlossen ✓") and goes. Without a running session it takes no space.
struct BibleSessionBar: View {
    let noteID: UUID
    let store: NoteStore
    /// Saves the text of the editor; runs before the session is completed.
    let saveText: () -> Void
    @Environment(\.locale) private var locale
    @State private var asking: BibleSessionEndModel?
    @State private var showsDone = false

    var body: some View {
        VStack(spacing: 0) {
            if let session = store.openSession(noteID: noteID), let model = model(for: session) {
                running(model)
            } else if showsDone {
                done
            }
        }
        .task(id: showsDone) {
            guard showsDone else { return }
            try? await Task.sleep(for: .seconds(2))
            showsDone = false
        }
    }

    private func model(for session: BibleStudySessionRecord) -> BibleSessionEndModel? {
        if let asking, asking.sessionID == session.id { return asking }
        return BibleSessionEndModel(session: session, store: store, locale: locale)
    }

    private func running(_ model: BibleSessionEndModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.runningTitle, systemImage: "book.pages")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Abschließen") {
                    if model.asksForEnd { asking = asking?.sessionID == model.sessionID ? nil : model } else { complete(model) }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("bibleSession.complete")
            }
            if asking?.sessionID == model.sessionID {
                BibleSessionEndForm(model: model) { complete(model) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var done: some View {
        Label("Sitzung abgeschlossen ✓", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.greenText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16)
            .background(Color.green.opacity(0.18))
            .accessibilityIdentifier("bibleSession.done")
            .onAppear { AccessibilityNotification.Announcement(String(localized: "Sitzung abgeschlossen")).post() }
    }

    private func complete(_ model: BibleSessionEndModel) {
        model.complete(beforeCompleting: saveText)
        asking = nil
        showsDone = true
    }
}

/// The wheels for the end of a session and the button that confirms them; shared by the bar and the sheet of the folder list.
struct BibleSessionEndForm: View {
    let model: BibleSessionEndModel
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bis wohin gelesen?").font(.subheadline).foregroundStyle(.secondaryText)
            HStack(spacing: 0) {
                Picker("Kapitel", selection: Binding(get: { model.end?.chapter ?? 1 },
                                                     set: { model.setEnd(chapter: $0, verse: model.end?.verse ?? 1) })) {
                    ForEach(model.chapterRange, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                Picker("Vers", selection: Binding(get: { model.end?.verse ?? 1 },
                                                  set: { model.setEnd(chapter: model.end?.chapter ?? 1, verse: $0) })) {
                    ForEach(model.verseRange(chapter: model.end?.chapter ?? 1), id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 120)
            Button(action: onConfirm) {
                Text(model.confirmTitle).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("bibleSession.confirm")
        }
    }
}

/// "Abschließen" in the folder list: the same question as in the note, as a sheet.
struct BibleSessionEndSheet: View {
    let model: BibleSessionEndModel
    let onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BibleSessionEndForm(model: model) {
                model.complete()
                dismiss()
                onCompleted()
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(model.runningTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
        .presentationDetents([.height(360)])
    }
}
