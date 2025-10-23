import Foundation

struct FuzzyMatcher {
    /// Fast fuzzy matching with scoring (higher is better)
    /// Supports space-separated terms that can match in any order
    static func match(query: String, against text: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        // Split query by spaces to allow out-of-order matching
        let terms = query.split(separator: " ").map { String($0) }

        // All terms must match
        var totalScore = 0
        for term in terms {
            guard let termScore = matchSingleTerm(term: term, against: text) else {
                return nil // If any term doesn't match, the whole match fails
            }
            totalScore += termScore
        }

        return max(totalScore, 1) // Ensure valid matches always have positive score
    }

    /// Match a single term (no spaces) against text
    private static func matchSingleTerm(term: String, against text: String) -> Int? {
        guard !term.isEmpty else { return 0 }

        let queryLower = term.lowercased()
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

        // Small penalty for length (prefer shorter matches but don't over-penalize)
        let lengthDiff = text.count - term.count
        if lengthDiff > 0 {
            score -= min(lengthDiff / 10, 10) // Max penalty of 10 points
        }

        return score
    }

    /// Filter and sort windows by fuzzy match score
    static func filterWindows(_ windows: [WindowInfo], query: String) -> [ScoredWindow] {
        guard !query.isEmpty else {
            return windows.map { ScoredWindow(window: $0, score: 0) }
        }

        return windows.compactMap { window in
            let titleScore = match(query: query, against: window.title) ?? 0
            let ownerScore = match(query: query, against: window.ownerName) ?? 0
            let displayScore = match(query: query, against: window.displayName) ?? 0

            let bestScore = max(titleScore, ownerScore, displayScore)

            guard bestScore > 0 else { return nil }

            return ScoredWindow(window: window, score: bestScore)
        }
        .sorted { $0.score > $1.score }
    }
}
