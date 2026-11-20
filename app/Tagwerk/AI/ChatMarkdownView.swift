import SwiftUI
import TagwerkCore

/// An assistant answer drawn from its Markdown (#225): headings, lists, bold and italic, links, code, tables.
///
/// It is drawn natively and not in a web view on purpose: a web view per message sizes itself asynchronously, which makes
/// a streaming answer jump inside the scrolling chat, and it would need its own copy of the text size and colours. Here the
/// answer is split into blocks by `ChatMarkdown` (pure rules, tested in TagwerkCore) and every block is a SwiftUI view, so
/// a streaming answer grows block by block with the same layout the finished message has.
///
/// Raw HTML never runs and nothing is loaded: the rules sanitize it first (see `ChatMarkdown`). Links open in Safari
/// through the system's `openURL`.
struct ChatMarkdownView: View {
    let text: String
    /// The sentence being read aloud (prepared text); it is highlighted where the answer contains it.
    var spokenSentence: String?

    var body: some View {
        ChatBlocksView(blocks: ChatMarkdown.blocks(text), spokenSentence: spokenSentence, spacing: 8)
    }
}

private struct ChatBlocksView: View {
    let blocks: [ChatBlock]
    let spokenSentence: String?
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // The position is the identity: while an answer streams, the blocks before the last one stay as they are.
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ChatBlockView(block: block, spokenSentence: spokenSentence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatBlockView: View {
    let block: ChatBlock
    let spokenSentence: String?

    var body: some View {
        switch block {
        case .paragraph(let text):
            inline(text)
        case .heading(let level, let text):
            inline(text)
                .font(Self.headingFont(level))
                .accessibilityAddTraits(.isHeader)
        case .code(_, let text):
            codeBlock(text)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(.secondary.opacity(0.5)).frame(width: 3)
                ChatBlocksView(blocks: blocks, spokenSentence: spokenSentence, spacing: 6).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            listView(list)
        case .table(let table):
            ChatTableView(table: table, spokenSentence: spokenSentence)
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: AttributedString) -> some View {
        Text(spokenSentence.map { SpokenAnswerText.highlighted(text, sentence: $0) } ?? text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.bold)
        case 2: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    private func codeBlock(_ code: String) -> some View {
        ScrollView(.horizontal) {
            Text(code)
                .font(.footnote.monospaced())
                .padding(10)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func listView(_ list: ChatList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(for: item, number: list.start + index, isOrdered: list.isOrdered)
                    ChatBlocksView(blocks: item.blocks, spokenSentence: spokenSentence, spacing: 4)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: ChatListItem, number: Int, isOrdered: Bool) -> some View {
        if let checked = item.checkbox {
            Image(systemName: checked ? "checkmark.square" : "square")
                .accessibilityLabel(checked ? Text("Erledigt") : Text("Offen"))
        } else if isOrdered {
            Text("\(number).").monospacedDigit().accessibilityHidden(false)
        } else {
            Text("•").accessibilityHidden(true)
        }
    }
}

/// A Markdown table: a grid that scrolls sideways when it is wider than the chat, with a bold head row and thin rules.
///
/// The width of every column is measured from its texts (at most `maximumColumnWidth`), because a grid sizes its rows
/// before it wraps text, which would cut off a long cell that has to wrap.
private struct ChatTableView: View {
    let table: ChatTable
    let spokenSentence: String?
    /// The widest a column gets before its text wraps; it follows the text size.
    @ScaledMetric(relativeTo: .subheadline) private var maximumColumnWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .subheadline) private var cellPadding: CGFloat = 8

    var body: some View {
        let widths = columnWidths()
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        self.cell(cell, column: column, width: widths[column], isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            self.cell(cell, column: column, width: widths[column], isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator)))
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// The text width of each column: its longest line, plus the cell padding, capped.
    private func columnWidths() -> [CGFloat] {
        let regular = UIFont.preferredFont(forTextStyle: .subheadline)
        let bold = UIFont.systemFont(ofSize: regular.pointSize, weight: .semibold)
        func width(of text: AttributedString, font: UIFont) -> CGFloat {
            String(text.characters).split(whereSeparator: \.isNewline)
                .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        }
        return table.alignments.indices.map { column in
            var widest = column < table.header.count ? width(of: table.header[column], font: bold) : 0
            for row in table.rows where column < row.count { widest = max(widest, width(of: row[column], font: regular)) }
            // A little reserve, because the measured width is the width of one line without kerning differences.
            return min(ceil(widest) + 4, maximumColumnWidth) + 2 * cellPadding
        }
    }

    private func cell(_ text: AttributedString, column: Int, width: CGFloat, isHeader: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        return Text(spokenSentence.map { SpokenAnswerText.highlighted(text, sentence: $0) } ?? text)
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .multilineTextAlignment(Self.textAlignment(alignment))
            .padding(.horizontal, cellPadding).padding(.vertical, 5)
            .frame(width: width, alignment: Self.frameAlignment(alignment))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity)
            .background(isHeader ? Color(.secondarySystemBackground) : .clear)
    }

    private static func frameAlignment(_ alignment: ChatColumnAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static func textAlignment(_ alignment: ChatColumnAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
