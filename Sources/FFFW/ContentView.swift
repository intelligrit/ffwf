import SwiftUI

struct ContentView: View {
    let hideWindow: () -> Void

    @ObservedObject private var windowManager = WindowManager.shared
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var previousResultCount = 0
    @State private var refreshTimer: Timer?
    @State private var resultLimit = 10
    @FocusState private var isSearchFocused: Bool

    private var allFilteredWindows: [ScoredWindow] {
        FuzzyMatcher.filterWindows(windowManager.windows, query: searchQuery)
    }

    private var filteredWindows: [ScoredWindow] {
        Array(allFilteredWindows.prefix(resultLimit))
    }

    private var hasMoreResults: Bool {
        allFilteredWindows.count > resultLimit
    }

    private var resultCountAnnouncement: String {
        let count = filteredWindows.count
        if count == 0 {
            return "No windows found"
        } else if count == 1 {
            return "1 window found"
        } else {
            return "\(count) windows found"
        }
    }

    private func announceSelectedWindow() {
        guard !filteredWindows.isEmpty, selectedIndex < filteredWindows.count else { return }

        let window = filteredWindows[selectedIndex].window
        let title = window.title.isEmpty ? window.ownerName : window.title
        let app = window.title.isEmpty ? "" : ", \(window.ownerName)"
        let announcement = "\(title)\(app)"

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
            TextField("Search windows...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .focused($isSearchFocused)
                .accessibilityLabel("Search for windows")
                .accessibilityHint("Type to filter windows by title or application name")
                .accessibilityValue(searchQuery.isEmpty ? "Empty" : searchQuery)
                .onSubmit {
                    selectWindow()
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
                        ForEach(Array(filteredWindows.enumerated()), id: \.element.id) { index, scoredWindow in
                        WindowRow(
                            window: scoredWindow.window,
                            isSelected: index == selectedIndex,
                            index: index + 1,
                            total: allFilteredWindows.count
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
                                Text("Show more (\(allFilteredWindows.count - resultLimit) remaining)")
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
                    .listStyle(.plain)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Window list")
                    .accessibilityHint("Use arrow keys to navigate, Enter to switch to window, Escape to close")
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .onChange(of: searchQuery) { _, _ in
                        selectedIndex = 0
                        resultLimit = 10 // Reset limit on new search

                        // Announce selected window immediately - speed is key
                        announceSelectedWindow()
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Search results")
            .accessibilityValue(resultCountAnnouncement)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            // Initial refresh
            windowManager.refreshWindows()
            searchQuery = ""
            selectedIndex = 0
            resultLimit = 10 // Reset limit on open

            // Start continuous background refresh every 0.5 seconds
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                windowManager.refreshWindows()
            }

            // Small delay to ensure window is ready before focusing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            // Stop the refresh timer when popover closes
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
                announceSelectedWindow()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredWindows.count - 1 {
                selectedIndex += 1
                announceSelectedWindow()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            hideWindow()
            return .handled
        }
    }

    private func selectWindow() {
        guard !filteredWindows.isEmpty, selectedIndex < filteredWindows.count else { return }
        let window = filteredWindows[selectedIndex].window
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
        let position = "Window \(index) of \(total)"
        let state = isSelected ? ", selected" : ""
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
                Text(window.title.isEmpty ? window.ownerName : window.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                if !window.title.isEmpty {
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
        .accessibilityHint("Press Enter to switch to this window")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
