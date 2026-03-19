import Foundation
import AppKit

enum WindowKind: Hashable {
    case window
    case terminalTab(windowTitle: String, tabTitle: String, tabIndex: Int)
    case chromeTab(windowTitle: String, tabTitle: String, tabIndex: Int)
    case slackWorkspace(name: String)
    case slackChannel(workspace: String, name: String)
    case slackDM(workspace: String, name: String)
    case messagesChat(chatID: String, handle: String, serviceType: String)
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

    var isTab: Bool {
        switch kind {
        case .terminalTab, .chromeTab:
            return true
        case .window, .slackWorkspace, .slackChannel, .slackDM, .messagesChat:
            return false
        }
    }

    var isSlackItem: Bool {
        switch kind {
        case .slackWorkspace, .slackChannel, .slackDM:
            return true
        case .window, .terminalTab, .chromeTab, .messagesChat:
            return false
        }
    }

    var isMessagesItem: Bool {
        if case .messagesChat = kind {
            return true
        }
        return false
    }

    var slackBadgeText: String? {
        switch kind {
        case .slackWorkspace:
            return "WORKSPACE"
        case .slackChannel:
            return "CHAN"
        case .slackDM:
            return "DM"
        case .window, .terminalTab, .chromeTab, .messagesChat:
            return nil
        }
    }

    var messagesBadgeText: String? {
        if case .messagesChat = kind {
            return "MSG"
        }
        return nil
    }

    var isTerminalTab: Bool {
        if case .terminalTab = kind {
            return true
        }
        return false
    }

    var isChromeTab: Bool {
        if case .chromeTab = kind {
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

    var tabIndex: Int? {
        switch kind {
        case .terminalTab(_, _, let tabIndex), .chromeTab(_, _, let tabIndex):
            return tabIndex
        case .window, .slackWorkspace, .slackChannel, .slackDM, .messagesChat:
            return nil
        }
    }
}

struct ScoredWindow: Identifiable {
    let window: WindowInfo
    let score: Int

    var id: Int { window.id }
}
