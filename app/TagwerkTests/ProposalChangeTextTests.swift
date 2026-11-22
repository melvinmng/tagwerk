import Testing
@testable import Tagwerk

/// The old value of each changed part of an adjusted card (mockup AN2a).
struct ProposalChangeTextTests {
    @Test func changedPart_carriesTheProposedText() throws {
        let parts = try #require(ProposalChangeText.parts(current: "Neue Aufgabe · fällig Mo. 23. Nov. · P3",
                                                          proposed: "Neue Aufgabe · fällig Fr. 27. Nov. · P3"))
        #expect(parts.map(\.proposed) == [nil, "fällig Fr. 27. Nov.", nil])
        #expect(parts.map(\.text) == ["Neue Aufgabe", "fällig Mo. 23. Nov.", "P3"])
    }

    @Test func separators_arePreserved() throws {
        let parts = try #require(ProposalChangeText.parts(current: "Issue · a\nNotizen: „x“", proposed: "Issue · a\nNotizen: „y“"))
        #expect(parts.map(\.separator) == [" · ", "\n", ""])
        #expect(parts.last?.proposed == "Notizen: „y“")
    }

    @Test func differentNumberOfParts_fallsBackToWholeText() {
        #expect(ProposalChangeText.parts(current: "A · B", proposed: "A") == nil)
    }

    @Test func spokenText_namesTheProposalOfTheModel() throws {
        let parts = try #require(ProposalChangeText.parts(current: "A · neu", proposed: "A · alt"))
        let spoken = ProposalChangeText.spoken(parts)
        #expect(spoken.hasPrefix("A · neu ("))
        #expect(spoken.contains("alt"))
    }

    @Test func unchangedText_hasNoStrikethrough() throws {
        let parts = try #require(ProposalChangeText.parts(current: "A · B", proposed: "A · B"))
        #expect(parts.allSatisfy { $0.proposed == nil })
        #expect(String(ProposalChangeText.attributed(parts).characters) == "A · B")
    }
}
