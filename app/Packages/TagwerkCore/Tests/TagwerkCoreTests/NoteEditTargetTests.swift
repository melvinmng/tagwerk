import Foundation
import Testing
@testable import TagwerkCore

struct NoteEditTargetTests {
    @Test func parse_lineAndEnd() {
        #expect(NoteEditTarget.parse("tagwerk-edit:12")?.line == 12)
        #expect(NoteEditTarget.parse("tagwerk-edit:12")?.isEnd == false)
        #expect(NoteEditTarget.parse("tagwerk-edit:end")?.line == nil)
        #expect(NoteEditTarget.parse("tagwerk-edit:end")?.isEnd == true)
        #expect(NoteEditTarget.parse("TAGWERK-EDIT:3")?.line == 3)
    }

    @Test func parse_rejectsOtherSchemes() {
        for url in ["tagwerk-toggle:3", "https://example.com", "tagwerk-edit:", "tagwerk-edit:0", "tagwerk-edit:-2", "tagwerk-edit:1x",
                    "tagwerk-edit:endx", "tagwerk-edit:١٢", "attachment:12", ""] {
            #expect(NoteEditTarget.parse(url) == nil, "\(url)")
        }
    }

    @Test func offset_endOfMiddleLine() {
        let text = "eins\nzwei\ndrei"
        #expect(NoteEditTarget.offset(endOfLine: 1, in: text) == 4)
        #expect(NoteEditTarget.offset(endOfLine: 2, in: text) == 9)
    }

    @Test func offset_lastLineWithoutBreak() {
        #expect(NoteEditTarget.offset(endOfLine: 3, in: "eins\nzwei\ndrei") == 14)
        #expect(NoteEditTarget.offset(endOfLine: 1, in: "allein") == 6)
    }

    @Test func offset_beyondTextClampsToEnd() {
        #expect(NoteEditTarget.offset(endOfLine: 99, in: "a\nb") == 3)
        #expect(NoteEditTarget.offset(endOfLine: 5, in: "") == 0)
        #expect(NoteEditTarget.offset(endOfLine: 0, in: "ab\ncd") == 2)
    }

    @Test func offset_crlf() {
        let text = "eins\r\nzwei\r\ndrei"
        // "\r\n" is one character of the string, so offsets match `String.index(offsetBy:)`.
        let first = NoteEditTarget.offset(endOfLine: 1, in: text)
        let second = NoteEditTarget.offset(endOfLine: 2, in: text)
        #expect(first == 4 && second == 9)
        #expect(text[text.index(text.startIndex, offsetBy: first)...].hasPrefix("\r\nzwei"))
    }

    @Test func offset_emoji() {
        let text = "a👨‍👩‍👧b\nzweite 🙂\ndritte"
        #expect(NoteEditTarget.offset(endOfLine: 1, in: text) == 3)
        let second = NoteEditTarget.offset(endOfLine: 2, in: text)
        #expect(text[text.index(text.startIndex, offsetBy: second)...].hasPrefix("\ndritte"))
    }

    @Test func approximateLine_skipsEmptyLines() {
        let text = "eins\n\n\n\nfünf\nsechs"
        // 6 lines; a tap at one third lands on the empty line 3, the next non-empty line below is 5.
        #expect(NoteEditTarget.approximateLine(fraction: 0.4, in: text) == 5)
        // Below the last non-empty line the search goes upwards.
        #expect(NoteEditTarget.approximateLine(fraction: 0.9, in: "a\nb\n\n\n") == 2)
    }

    @Test func approximateLine_zeroAndOne() {
        let text = "eins\nzwei\ndrei"
        #expect(NoteEditTarget.approximateLine(fraction: 0, in: text) == 1)
        #expect(NoteEditTarget.approximateLine(fraction: 1, in: text) == 3)
        #expect(NoteEditTarget.approximateLine(fraction: -3, in: text) == 1)
        #expect(NoteEditTarget.approximateLine(fraction: 7, in: text) == 3)
        #expect(NoteEditTarget.approximateLine(fraction: .nan, in: text) == 1)
        #expect(NoteEditTarget.approximateLine(fraction: 0.5, in: "") == 1)
        #expect(NoteEditTarget.approximateLine(fraction: 0.5, in: "\n\n") == 2)
    }

    @Test func line_atOffset() {
        let text = "eins\nzwei\n\ndrei"
        #expect(NoteEditTarget.line(atOffset: 0, in: text) == 1)
        #expect(NoteEditTarget.line(atOffset: 4, in: text) == 1)
        #expect(NoteEditTarget.line(atOffset: 5, in: text) == 2)
        #expect(NoteEditTarget.line(atOffset: 10, in: text) == 3)
        #expect(NoteEditTarget.line(atOffset: 11, in: text) == 4)
        #expect(NoteEditTarget.line(atOffset: 99, in: text) == 4)
        #expect(NoteEditTarget.line(atOffset: -3, in: text) == 1)
        #expect(NoteEditTarget.line(atOffset: 0, in: "") == 1)
        // The inverse of the end of a line, also with "\r\n".
        for line in 1...4 { #expect(NoteEditTarget.line(atOffset: NoteEditTarget.offset(endOfLine: line, in: text), in: text) == line) }
        #expect(NoteEditTarget.line(atOffset: 6, in: "a\r\nb\r\nc") == 3)
    }
}
