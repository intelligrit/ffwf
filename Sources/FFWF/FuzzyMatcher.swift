import Foundation

// Concurrent processing extension for better performance
extension Array {
    func concurrentCompactMap<T>(_ transform: @escaping (Element) -> T?) -> [T] {
        let lock = NSLock()
        var results: [T] = []

        DispatchQueue.concurrentPerform(iterations: self.count) { index in
            if let result = transform(self[index]) {
                lock.lock()
                results.append(result)
                lock.unlock()
            }
        }

        return results
    }
}

struct FuzzyMatcher {

    /// Filter and sort windows by fuzzy match score
    static func filterWindows(_ windows: [WindowInfo], query: String) -> [ScoredWindow] {
        guard !query.isEmpty else {
            return windows.map { ScoredWindow(window: $0, score: 0) }
        }

        // Use concurrent processing for large window lists
        let matches: [ScoredWindow]
        if windows.count > 50 {
            // Parallel processing for large lists
            matches = windows.concurrentCompactMap { window in
                let titleScore = matchPreLowered(query: query, againstLower: window.titleLower, original: window.title) ?? 0
                let ownerScore = matchPreLowered(query: query, againstLower: window.ownerNameLower, original: window.ownerName) ?? 0

                // Prefer title matches over app name matches (1.5x multiplier)
                let weightedTitleScore = Int(Double(titleScore) * 1.5)
                let bestScore = max(weightedTitleScore, ownerScore)

                guard bestScore > 0 else { return nil }
                return ScoredWindow(window: window, score: bestScore)
            }
        } else {
            // Sequential for small lists (less overhead)
            matches = windows.compactMap { window in
                let titleScore = matchPreLowered(query: query, againstLower: window.titleLower, original: window.title) ?? 0
                let ownerScore = matchPreLowered(query: query, againstLower: window.ownerNameLower, original: window.ownerName) ?? 0

                // Prefer title matches over app name matches (1.5x multiplier)
                let weightedTitleScore = Int(Double(titleScore) * 1.5)
                let bestScore = max(weightedTitleScore, ownerScore)

                guard bestScore > 0 else { return nil }
                return ScoredWindow(window: window, score: bestScore)
            }
        }

        return matches.sorted { $0.score > $1.score }
    }

    /// Fast matching using pre-lowercased text
    private static func matchPreLowered(query: String, againstLower textLower: String, original text: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let queryLower = query.lowercased()

        // Exact match bonus - prioritize exact matches
        if textLower == queryLower {
            return 10000 // Exact match always wins
        }

        // Starts with query bonus - strong preference
        if textLower.hasPrefix(queryLower) {
            return 5000 + (queryLower.count * 10) // Prefix match is very strong
        }

        // Split query by spaces to allow out-of-order matching
        let terms = query.split(separator: " ").map { String($0) }

        // All terms must match
        var totalScore = 0
        for term in terms {
            guard let termScore = matchSingleTermPreLowered(term: term, againstLower: textLower, original: text) else {
                return nil // If any term doesn't match, the whole match fails
            }
            totalScore += termScore
        }

        return max(totalScore, 1) // Ensure valid matches always have positive score
    }

    /// Match a single term using pre-lowercased text
    private static func matchSingleTermPreLowered(term: String, againstLower textLower: String, original text: String) -> Int? {
        guard !term.isEmpty else { return 0 }

        let queryLower = term.lowercased()

        var score = 0
        var queryIndex = queryLower.startIndex
        var textIndex = textLower.startIndex
        var lastMatchIndex: String.Index? = nil
        var firstMatchPosition: Int? = nil
        var consecutiveMatches = 0
        var totalGapDistance = 0
        var currentPosition = 0

        while queryIndex < queryLower.endIndex && textIndex < textLower.endIndex {
            let queryChar = queryLower[queryIndex]
            let textChar = textLower[textIndex]

            if queryChar == textChar {
                // Track first match position for early bonus
                if firstMatchPosition == nil {
                    firstMatchPosition = currentPosition
                }

                // Base score for match
                score += 1

                // Bonus for consecutive matches
                if let lastIndex = lastMatchIndex, textLower.index(after: lastIndex) == textIndex {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 0

                    // Calculate gap distance between non-consecutive matches
                    if let lastIndex = lastMatchIndex {
                        let gap = textLower.distance(from: lastIndex, to: textIndex) - 1
                        totalGapDistance += gap
                    }
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
            currentPosition += 1
        }

        // Must match all query characters
        guard queryIndex == queryLower.endIndex else { return nil }

        // Early position bonus - matches in first 25% of string get bonus
        if let firstPos = firstMatchPosition {
            let textLength = textLower.count
            let earlyThreshold = max(1, textLength / 4)
            if firstPos < earlyThreshold {
                let earlyBonus = 20 - (firstPos * 20 / earlyThreshold) // Up to 20 points
                score += earlyBonus
            }
        }

        // Character distance penalty - penalize large gaps between matches
        // Each character gap costs 1 point, but capped to avoid over-penalizing
        let gapPenalty = min(totalGapDistance / 2, 30) // Max penalty of 30 points
        score -= gapPenalty

        // Small penalty for length (prefer shorter matches but don't over-penalize)
        let lengthDiff = text.count - term.count
        if lengthDiff > 0 {
            score -= min(lengthDiff / 10, 10) // Max penalty of 10 points
        }

        // Ensure valid matches always have positive score
        return max(score, 1)
    }
}
