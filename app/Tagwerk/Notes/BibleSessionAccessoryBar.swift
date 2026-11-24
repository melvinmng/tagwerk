import SwiftUI
import TagwerkCore

/// The capsule above the tab bar while a Bible Study session is open (2B of the device round, #307): "Sitzung läuft · Römer ab
/// 3,21 · seit 09:41". A tap leads from every tab back into the note, "Abschließen" asks "Bis wohin gelesen?". It sits in the
/// accessory of the tab bar like the focus bar and gives way to it while a focus session runs (the tab bar has one accessory). In the
/// small placement of the tab bar (the bar is minimised) only the symbol and the title remain.
struct BibleSessionAccessoryBar: View {
    let session: BibleStudySessionRecord
    let store: NoteStore
    let onOpen: () -> Void
    let onComplete: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.locale) private var locale

    var body: some View {
        let title = BibleSessionEndModel(session: session, store: store, locale: locale)?.runningTitle
            ?? String(localized: "Sitzung läuft · \(NotesListView.sessionTitle(session, locale: locale))")
        let since = session.startedAt.formatted(.dateTime.hour().minute().locale(locale))
        let hint = String(localized: "seit \(since) · tippen zum Weiterschreiben")
        let isCompact = placement == .inline
        HStack(spacing: 10) {
            Image(systemName: "book.pages").font(.body.weight(.semibold)).foregroundStyle(.tint).frame(width: 26)
            if isCompact {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(hint).font(.caption).foregroundStyle(.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Abschließen", action: onComplete)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        // One element for VoiceOver: the state as a sentence, the end as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("bibleSession.capsule")
        .accessibilityLabel(Text("\(title), \(hint)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Abschließen"), onComplete)
    }
}
