import SwiftUI
import TagwerkCore

/// What the group list shows of one entry.
struct CollapsedGroupRow: Identifiable, Equatable {
    let entry: DayEntry
    /// "10:00–11:00".
    let time: String
    let title: String
    /// Marks after the time ("Frei", "↻", deadline text), already prefixed with " · "; empty without marks.
    let suffix: String
    let color: Color

    var id: String { entry.id }
}

/// Entries that overlap and would get columns narrower than about six characters, as one block over the full width
/// (BF1c): "3 Termine · 10:00–11:00" and the titles; a tap opens the entries as a list. Neutral grey, a red bar on the
/// left when a deadline is among them, the frame of a running entry when one of them runs.
struct CollapsedGroupBlock: View {
    let count: Int
    /// "10:00–11:00".
    let timeText: String
    /// Start and end for VoiceOver ("10:00" and "11:00").
    let startText: String
    let endText: String
    let titles: [String]
    let hasDeadline: Bool
    let isRunning: Bool
    let height: CGFloat
    let action: () -> Void

    /// One line of the caption font at the current size.
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 16
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let padding: CGFloat = 6

    var body: some View {
        // The headline wraps to a second line with accessibility sizes instead of being cut off.
        let headlineLines = typeSize.isAccessibilitySize ? 2 : 1
        let slots = max(0, Int((height - 2 * Self.padding - CGFloat(headlineLines) * lineHeight) / lineHeight))
        let shownTitles = Self.visibleTitles(titles, slots: slots)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) Termine · \(timeText)").font(.caption.weight(.semibold)).lineLimit(headlineLines)
                    // The text node takes the whole width and its own height: the audit reports a text in a fixed frame as clipped.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(shownTitles.lines.enumerated()), id: \.offset) { _, title in
                    Text(title).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                if shownTitles.hidden > 0 {
                    Text("+\(shownTitles.hidden) weitere").font(.caption).foregroundStyle(.gridTimeText).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.gray.opacity(0.24), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isRunning ? Color.gray : .clear, lineWidth: 2)
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(hasDeadline ? Color.red : Color.gray).frame(width: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7))
            }
            .contentShape(Rectangle())
            // A short group at a large text size cannot hold its headline: it is cut at the block, not drawn over the entries around.
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(count) Termine, \(startText) bis \(endText): \(titles.joined(separator: ", "))"))
        .accessibilityAddTraits(.isButton)
    }

    /// The titles that fit into `slots` lines; when not all fit, the last line says how many are left out
    /// ("+2 weitere"), so at least one title and that line are shown when there is room for two lines.
    static func visibleTitles(_ titles: [String], slots: Int) -> (lines: [String], hidden: Int) {
        if titles.count <= slots { return (titles, 0) }
        guard slots >= 2 else { return ([], titles.count) }
        let shown = slots - 1
        return (Array(titles.prefix(shown)), titles.count - shown)
    }
}

/// The entries of a collapsed group as a list in a sheet (time, title and marks per row). A row hands its entry to
/// `onOpen`, which closes this sheet first and opens the entry afterwards (no sheet over a sheet).
struct CollapsedGroupList: View {
    let rows: [CollapsedGroupRow]
    let onOpen: (DayEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        Button { onOpen(row.entry) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                RoundedRectangle(cornerRadius: 2).fill(row.color).frame(width: 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).foregroundStyle(.primary)
                                    Text(row.time + row.suffix).font(.caption).foregroundStyle(.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Zum Verschieben den Eintrag öffnen.")
                }
            }
            .navigationTitle("\(rows.count) Termine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A group the user tapped; the sheet shows its rows.
struct CollapsedGroup: Identifiable, Equatable {
    let rows: [CollapsedGroupRow]
    var id: String { rows.map(\.id).joined(separator: "|") }
}
