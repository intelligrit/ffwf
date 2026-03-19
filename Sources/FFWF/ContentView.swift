import SwiftUI

struct ContentView: View {
    let hideWindow: () -> Void

    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var searchHistory = SearchHistory.shared
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var previousResultCount = 0
    @State private var refreshTimer: Timer?
    @State private var resultLimit = 10
    @State private var historyNavigationIndex: Int? = nil
    @FocusState private var isSearchFocused: Bool

    private var allFilteredItems: [ScoredWindow] {
        FuzzyMatcher.filterWindows(windowManager.windows, query: searchQuery)
    }

    private var filteredItems: [ScoredWindow] {
        Array(allFilteredItems.prefix(resultLimit))
    }

    private var hasMoreResults: Bool {
        allFilteredItems.count > resultLimit
    }

    private var resultCountAnnouncement: String {
        let count = filteredItems.count
        if count == 0 {
            return "No results found"
        } else if count == 1 {
            return "1 result found"
        } else {
            return "\(count) results found"
        }
    }

    private var selectedAnnouncementToken: String {
        guard historyNavigationIndex == nil,
              !filteredItems.isEmpty,
              selectedIndex < filteredItems.count else {
            return ""
        }

        let item = filteredItems[selectedIndex].window
        return "\(selectedIndex)|\(item.id)|\(item.title)|\(item.ownerName)"
    }

    private func announceSelectedItem() {
        guard !filteredItems.isEmpty, selectedIndex < filteredItems.count else { return }

        let item = filteredItems[selectedIndex].window
        let title = item.title.isEmpty ? item.ownerName : item.title
        let announcement: String
        if item.isTab {
            let tabPrefix: String
            if let tabIndex = item.tabIndex {
                tabPrefix = "tab \(tabIndex)"
            } else {
                tabPrefix = "tab"
            }
            announcement = "\(tabPrefix) \(title), \(item.ownerName)"
        } else {
            let app = item.title.isEmpty ? "" : ", \(item.ownerName)"
            announcement = "\(title)\(app)"
        }

        // Post announcement directly to the application
        DispatchQueue.main.async {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            TextField("Search windows and tabs...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .focused($isSearchFocused)
                .accessibilityLabel("Search for windows and tabs")
                .accessibilityHint("Type to filter windows, tabs, and application names")
                .accessibilityValue(searchQuery.isEmpty ? "Empty" : searchQuery)
                .onSubmit {
                    // If in history mode, select the highlighted history item
                    if searchQuery.isEmpty, let index = historyNavigationIndex {
                        let recentSearches = searchHistory.recentSearches()
                        if index < recentSearches.count {
                            searchQuery = recentSearches[index]
                            historyNavigationIndex = nil
                        }
                    } else {
                        selectWindow()
                    }
                }

            Divider()

            // Results list
            ScrollViewReader { proxy in
                if windowManager.windows.isEmpty {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading windows...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Show recent searches when query is empty
                        if searchQuery.isEmpty {
                            Section(header: Text("Recent Searches").font(.system(size: 12))) {
                                ForEach(Array(searchHistory.recentSearches().enumerated()), id: \.offset) { index, historyItem in
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary)
                                        Text(historyItem)
                                            .font(.system(size: 14))
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(historyNavigationIndex == index ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .cornerRadius(4)
                                    .contentShape(Rectangle())
                                    .id("history-\(index)")
                                    .onTapGesture {
                                        searchQuery = historyItem
                                    }
                                }
                            }
                        }

                        // Windows section
                        if !searchQuery.isEmpty || searchHistory.recentSearches().isEmpty {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, scoredWindow in
                                WindowRow(
                                    window: scoredWindow.window,
                                    isSelected: index == selectedIndex,
                                    index: index + 1,
                                    total: allFilteredItems.count
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    selectWindow()
                                }
                            }

                            // "More results" button
                            if hasMoreResults {
                                Button(action: {
                                    resultLimit *= 2
                                }) {
                                    HStack {
                                        Spacer()
                                        Text("Show more (\(allFilteredItems.count - resultLimit) remaining)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Result list")
                    .accessibilityHint("Use arrow keys to navigate, Enter to switch to the selected result, Escape to close")
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .onChange(of: historyNavigationIndex) { _, newValue in
                        if let index = newValue {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("history-\(index)", anchor: .center)
                            }
                        }
                    }
                    .onChange(of: selectedAnnouncementToken) { oldValue, newValue in
                        guard !newValue.isEmpty, oldValue != newValue else { return }
                        announceSelectedItem()
                    }
                    .onChange(of: searchQuery) { _, _ in
                        selectedIndex = 0
                        resultLimit = 10 // Reset limit on new search
                        historyNavigationIndex = nil
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Search results")
            .accessibilityValue(resultCountAnnouncement)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            // Start with empty search
            searchQuery = ""
            selectedIndex = 0
            resultLimit = 10
            historyNavigationIndex = nil

            // Start background refresh while window is visible
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                windowManager.refreshWindows()
            }

            // Initial refresh
            windowManager.refreshWindows()

            // Focus the search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            // Stop the refresh timer when popover closes
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onKeyPress(.tab) {
            // Autocomplete with tab
            if let completion = searchHistory.autocomplete(for: searchQuery) {
                searchQuery = completion
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            // Navigate history when search is empty
            if searchQuery.isEmpty && !searchHistory.recentSearches().isEmpty {
                if let currentIndex = historyNavigationIndex {
                    // Move up in the list (decrement index, but don't go below 0)
                    if currentIndex > 0 {
                        historyNavigationIndex = currentIndex - 1
                    }
                } else {
                    // Start at the first item
                    historyNavigationIndex = 0
                }
            } else if !filteredItems.isEmpty {
                // Navigate results
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            // Navigate history when search is empty
            if searchQuery.isEmpty && !searchHistory.recentSearches().isEmpty {
                let recentSearches = searchHistory.recentSearches()
                if let currentIndex = historyNavigationIndex {
                    // Move down in the list (increment index)
                    if currentIndex < recentSearches.count - 1 {
                        historyNavigationIndex = currentIndex + 1
                    }
                } else {
                    // Start at the first item
                    historyNavigationIndex = 0
                }
            } else if !searchQuery.isEmpty && !filteredItems.isEmpty {
                // Navigate results
                if selectedIndex < filteredItems.count - 1 {
                    selectedIndex += 1
                }
            }
            return .handled
        }
        .onKeyPress(.escape) {
            hideWindow()
            return .handled
        }
    }

    private func selectWindow() {
        guard !filteredItems.isEmpty, selectedIndex < filteredItems.count else { return }
        let window = filteredItems[selectedIndex].window

        // Save search to history if not empty
        if !searchQuery.isEmpty {
            searchHistory.addSearch(searchQuery)
        }

        windowManager.activateWindow(window)
        hideWindow()
    }
}

struct WindowRow: View {
    let window: WindowInfo
    let isSelected: Bool
    let index: Int
    let total: Int

    var accessibilityDescription: String {
        let title = window.title.isEmpty ? window.ownerName : window.title
        let app = window.title.isEmpty ? "" : ", \(window.ownerName)"
        let role = window.isTab ? "Tab" : "Window"
        let position = "\(role) \(index) of \(total)"
        let state = isSelected ? ", selected" : ""
        if window.isTab {
            let tabPrefix: String
            if let tabIndex = window.tabIndex {
                tabPrefix = "tab \(tabIndex)"
            } else {
                tabPrefix = "tab"
            }
            let subtitle = window.subtitle.map { ", \($0)" } ?? ""
            return "\(tabPrefix) \(title)\(subtitle)\(app). \(position)\(state)"
        }
        return "\(title)\(app). \(position)\(state)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon (cached)
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if window.isTab {
                        Text("TAB")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(window.title.isEmpty ? window.ownerName : window.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }

                if let subtitle = window.subtitle {
                    Text("\(subtitle) · \(window.ownerName)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if !window.title.isEmpty {
                    Text(window.ownerName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
        .cornerRadius(4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(window.isTab ? "Press Enter to switch to this tab" : "Press Enter to switch to this window")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
