import SwiftUI

struct ContentView: View {
    let hideWindow: () -> Void

    @StateObject private var windowManager = WindowManager()
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredWindows: [ScoredWindow] {
        FuzzyMatcher.filterWindows(windowManager.windows, query: searchQuery)
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
                .onSubmit {
                    selectWindow()
                }

            Divider()

            // Results list
            ScrollViewReader { proxy in
                List(Array(filteredWindows.enumerated()), id: \.element.id) { index, scoredWindow in
                    WindowRow(
                        window: scoredWindow.window,
                        isSelected: index == selectedIndex
                    )
                    .id(index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndex = index
                        selectWindow()
                    }
                }
                .listStyle(.plain)
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: searchQuery) { _, _ in
                    selectedIndex = 0
                }
            }
        }
        .frame(width: 600, height: 400)
        .onAppear {
            windowManager.refreshWindows()
            searchQuery = ""
            selectedIndex = 0
            // Small delay to ensure window is ready before focusing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredWindows.count - 1 {
                selectedIndex += 1
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

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let app = NSRunningApplication(processIdentifier: window.processID),
               let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
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
    }
}
