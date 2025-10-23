import Foundation
import AppKit

struct WindowInfo: Identifiable, Hashable {
    let id: Int
    let title: String
    let ownerName: String
    let processID: pid_t
    let windowNumber: Int
    let icon: NSImage? // Cache the icon

    // Pre-lowercased for faster fuzzy matching
    let titleLower: String
    let ownerNameLower: String

    // Tab information (for Chrome, Terminal, etc.)
    let isTab: Bool
    let tabIndex: Int?
    let windowIndex: Int?

    init(id: Int, title: String, ownerName: String, processID: pid_t, windowNumber: Int, icon: NSImage?, isTab: Bool = false, tabIndex: Int? = nil, windowIndex: Int? = nil) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.processID = processID
        self.windowNumber = windowNumber
        self.icon = icon
        self.titleLower = title.lowercased()
        self.ownerNameLower = ownerName.lowercased()
        self.isTab = isTab
        self.tabIndex = tabIndex
        self.windowIndex = windowIndex
    }

    // Custom Hashable implementation since NSImage isn't Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(processID)
        hasher.combine(windowNumber)
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.ownerName == rhs.ownerName &&
        lhs.processID == rhs.processID &&
        lhs.windowNumber == rhs.windowNumber
    }

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
