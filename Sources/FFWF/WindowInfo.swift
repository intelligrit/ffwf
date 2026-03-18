import Foundation
import AppKit

enum WindowKind: Hashable {
    case window
    case terminalTab(windowTitle: String, tabTitle: String, tabIndex: Int)
}

struct WindowInfo: Identifiable, Hashable {
    let id: Int
    let title: String
    let ownerName: String
    let processID: pid_t
    let windowNumber: Int
    let kind: WindowKind
    let subtitle: String?
    let detailText: String
    let icon: NSImage? // Cache the icon

    // Pre-lowercased for faster fuzzy matching
    let titleLower: String
    let ownerNameLower: String
    let subtitleLower: String
    let detailTextLower: String

    init(
        id: Int,
        title: String,
        ownerName: String,
        processID: pid_t,
        windowNumber: Int,
        kind: WindowKind = .window,
        subtitle: String? = nil,
        detailText: String = "",
        icon: NSImage?
    ) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.processID = processID
        self.windowNumber = windowNumber
        self.kind = kind
        self.subtitle = subtitle
        self.detailText = detailText
        self.icon = icon
        self.titleLower = title.lowercased()
        self.ownerNameLower = ownerName.lowercased()
        self.subtitleLower = subtitle?.lowercased() ?? ""
        self.detailTextLower = detailText.lowercased()
    }

    // Custom Hashable implementation since NSImage isn't Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(processID)
        hasher.combine(windowNumber)
        hasher.combine(kind)
        hasher.combine(subtitle)
        hasher.combine(detailText)
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.ownerName == rhs.ownerName &&
        lhs.processID == rhs.processID &&
        lhs.windowNumber == rhs.windowNumber &&
        lhs.kind == rhs.kind &&
        lhs.subtitle == rhs.subtitle &&
        lhs.detailText == rhs.detailText
    }

    var displayName: String {
        if title.isEmpty {
            return ownerName
        }
        return "\(ownerName): \(title)"
    }

    var isTerminalTab: Bool {
        if case .terminalTab = kind {
            return true
        }
        return false
    }

    var terminalTabIndex: Int? {
        if case .terminalTab(_, _, let tabIndex) = kind {
            return tabIndex
        }
        return nil
    }
}

struct ScoredWindow: Identifiable {
    let window: WindowInfo
    let score: Int

    var id: Int { window.id }
}
