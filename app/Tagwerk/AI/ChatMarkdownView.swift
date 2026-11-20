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
private struct ChatTableView: View {
    let table: ChatTable
    let spokenSentence: String?

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        self.cell(cell, column: column, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            self.cell(cell, column: column, isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator)))
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func cell(_ text: AttributedString, column: Int, isHeader: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        return Text(spokenSentence.map { SpokenAnswerText.highlighted(text, sentence: $0) } ?? text)
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .padding(.horizontal, 8).padding(.vertical, 5)
            // A long cell wraps instead of making the table arbitrarily wide; the outer frame fills the column.
            .frame(maxWidth: 240, alignment: Self.frameAlignment(alignment))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.frameAlignment(alignment))
            .background(isHeader ? Color(.secondarySystemBackground) : .clear)
    }

    private static func frameAlignment(_ alignment: ChatColumnAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
