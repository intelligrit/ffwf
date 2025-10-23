import Foundation

struct FuzzyMatcher {
    /// Fast fuzzy matching with scoring (higher is better)
    /// Uses a simple but efficient algorithm inspired by Sublime Text
    static func match(query: String, against text: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let queryLower = query.lowercased()
        let textLower = text.lowercased()

        var score = 0
        var queryIndex = queryLower.startIndex
        var textIndex = textLower.startIndex
        var lastMatchIndex: String.Index? = nil
        var consecutiveMatches = 0

        while queryIndex < queryLower.endIndex && textIndex < textLower.endIndex {
            let queryChar = queryLower[queryIndex]
            let textChar = textLower[textIndex]

            if queryChar == textChar {
                // Base score for match
                score += 1

                // Bonus for consecutive matches
                if let lastIndex = lastMatchIndex, textLower.index(after: lastIndex) == textIndex {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 0
                }

                // Bonus for match at word boundary
                if textIndex == textLower.startIndex ||
                   (textIndex > textLower.startIndex &&
                    !textLower[textLower.index(before: textIndex)].isLetter) {
                    score += 10
                }

                // Bonus for uppercase match in original text
                if textIndex < text.endIndex && text[textIndex].isUppercase {
                    score += 5
                }

                lastMatchIndex = textIndex
                queryIndex = queryLower.index(after: queryIndex)
            }

            textIndex = textLower.index(after: textIndex)
        }

        // Must match all query characters
        guard queryIndex == queryLower.endIndex else { return nil }

        // Penalty for length (shorter matches are better)
        score -= (text.count - query.count) / 2

        return score
    }

    /// Filter and sort windows by fuzzy match score
    static func filterWindows(_ windows: [WindowInfo], query: String) -> [ScoredWindow] {
        guard !query.isEmpty else {
            return windows.map { ScoredWindow(window: $0, score: 0) }
        }

        return windows.compactMap { window in
            let titleScore = match(query: query, against: window.title) ?? -1
            let ownerScore = match(query: query, against: window.ownerName) ?? -1
            let displayScore = match(query: query, against: window.displayName) ?? -1

            let bestScore = max(titleScore, ownerScore, displayScore)

            guard bestScore >= 0 else { return nil }

            return ScoredWindow(window: window, score: bestScore)
        }
        .sorted { $0.score > $1.score }
    }
}
