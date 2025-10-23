import Foundation

struct WindowInfo: Identifiable, Hashable {
    let id: Int
    let title: String
    let ownerName: String
    let processID: pid_t
    let windowNumber: Int

    var displayName: String {
        if title.isEmpty {
            return ownerName
        }
        return "\(ownerName): \(title)"
    }
}

struct ScoredWindow: Identifiable {
    let window: WindowInfo
    let score: Int

    var id: Int { window.id }
}
