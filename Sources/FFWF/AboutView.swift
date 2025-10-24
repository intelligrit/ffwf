import SwiftUI

struct Contributor: Identifiable {
    let id = UUID()
    let name: String
    let username: String
    let email: String
}

struct AboutView: View {
    let version: String

    private let contributors = [
        Contributor(name: "Robert Melton", username: "robertmeta", email: "robertmeta@gmail.com")
    ]

    var body: some View {
        VStack(spacing: 20) {
            // App Icon or Logo
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            // Title
            Text("FFWF")
                .font(.title)
                .fontWeight(.bold)

            Text("Fast Fuzzy Window Finder")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Version \(version)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Description
            Text("A blazing-fast macOS menu bar app for switching windows with fuzzy search.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider()

            // Contributors Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Contributors")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(contributors) { contributor in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(contributor.name)
                                        .fontWeight(.medium)
                                    Text("(\(contributor.username))")
                                        .foregroundColor(.secondary)
                                }
                                Text(contributor.email)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 150)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Divider()

            // Company Info
            VStack(spacing: 4) {
                Text("An Intelligrit Labs Product")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("© 2025 Intelligrit, LLC")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("MIT Licensed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Website Button
            Button(action: {
                if let url = URL(string: "https://intelligrit.com/labs/") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Visit Intelligrit Labs")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.link)
        }
        .padding()
        .frame(width: 400, height: 550)
    }
}
