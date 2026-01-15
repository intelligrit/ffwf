import Foundation

class SearchHistory: ObservableObject {
    static let shared = SearchHistory()

    private let maxHistorySize = 1000
    private let userDefaultsKey = "searchHistory"

    @Published private(set) var history: [String] = []

    init() {
        loadHistory()
    }

    func addSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Remove if already exists (move to front)
        history.removeAll { $0 == trimmed }

        // Add to front
        history.insert(trimmed, at: 0)

        // Keep only last maxHistorySize items
        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }

        saveHistory()
    }

    func recentSearches(limit: Int = 10) -> [String] {
        Array(history.prefix(limit))
    }

    func autocomplete(for query: String) -> String? {
        guard !query.isEmpty else { return nil }
        return history.first { $0.lowercased().hasPrefix(query.lowercased()) }
    }

    private func saveHistory() {
        UserDefaults.standard.set(history, forKey: userDefaultsKey)
    }

    private func loadHistory() {
        if let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            history = saved
        }
    }
}
