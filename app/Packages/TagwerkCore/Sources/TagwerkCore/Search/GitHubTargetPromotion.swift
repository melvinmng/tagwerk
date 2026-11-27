import Foundation

extension SearchResults {
    /// Shortest query (after trimming) that can move "Repositories & Projekte" to the top of the list.
    public static let githubPromotionMinimumLength = 3

    /// Whether the section "Repositories & Projekte" moves in front of all other sections. By default it stays before "Einstellungen",
    /// because a search for an appointment or a task should show those first. It moves up only when the query names a repository or a
    /// project: every word of the query (at least `githubPromotionMinimumLength` characters in all) is exactly the name or the start of
    /// a word of the name of one of `matches` ("tagwerk" finds "tagwerk" and "tagwerk-docs", "bericht" does not find "wochenbericht"),
    /// or the query is the start of "owner/name" and reaches into the name ("melvinmng/tag"). A hit that is only found by its owner
    /// does not count, and neither does a hit inside a word. Case, accents and umlauts are ignored (`SearchText.fold`).
    ///
    /// `matches` are the hits of the section for `query`; the rule does not filter them again.
    public static func promotesGitHubTargets(query: String, matches: [GitHubTargetSearchItem]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= githubPromotionMinimumLength else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map { SearchText.fold(String($0)) }
        guard !words.isEmpty else { return false }
        return matches.contains { item in words.allSatisfy(item.nameStarts(with:)) }
    }
}

extension GitHubTargetSearchItem {
    /// `foldedWord` is the start of a word of the title, or (repositories) the start of "owner/name" with at least one character of
    /// the name behind the slash. The owner alone is no name.
    func nameStarts(with foldedWord: String) -> Bool {
        if ChoiceFilter.startsAWord(foldedWord, in: SearchText.fold(title)) { return true }
        guard kind == .repository, let slash = foldedWord.firstIndex(of: "/"),
              foldedWord.index(after: slash) != foldedWord.endIndex else { return false }
        return SearchText.fold(targetID).hasPrefix(foldedWord)
    }
}
