//
//  OfflineModeView.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 8: Offline Mode Support
//

import SwiftUI

/// Informational view shown in the "Offline" tab when device is offline
/// Explains what features are available and unavailable
struct OfflineModeView: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @Binding var selectedTab: Tab

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                // Offline icon
                Image(systemName: "wifi.slash")
                    .font(.system(size: 70))
                    .foregroundColor(.orange)

                // Title
                Text("You're Offline")
                    .font(.title)
                    .fontWeight(.bold)

                // Description
                Text("Catalog, Browse, and Search require an internet connection.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Available features card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Available Offline")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        OfflineFeatureRow(
                            icon: "books.vertical",
                            title: "Your Library",
                            description: "Browse your cached library books"
                        )

                        OfflineFeatureRow(
                            icon: "arrow.down.circle.fill",
                            title: "Downloads",
                            description: "Play downloaded audiobooks"
                        )

                        OfflineFeatureRow(
                            icon: "clock",
                            title: "Playback Progress",
                            description: "Syncs when you're back online"
                        )
                    }
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 24)

                // Action buttons
                VStack(spacing: 12) {
                    // Retry connection button - refreshes network status and switches tab if connected
                    Button {
                        DebugLogger.network("Retry button tapped - current isConnected: \(networkMonitor.isConnected)")
                        // Force refresh the network status
                        networkMonitor.refreshStatus()
                        // Check if we're actually connected now
                        DebugLogger.network("After refresh - isConnected: \(networkMonitor.isConnected)")
                        if networkMonitor.isConnected {
                            DebugLogger.network("Connected! Switching to Catalog tab")
                            selectedTab = .catalog
                        } else {
                            DebugLogger.network("Still offline after refresh")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Connection")
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)

                    Button {
                        selectedTab = .library
                    } label: {
                        HStack {
                            Image(systemName: "books.vertical")
                            Text("Go to Library")
                        }
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 24)

                    Button {
                        selectedTab = .downloads
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Go to Downloads")
                        }
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Connection status with live indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(networkMonitor.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(networkMonitor.isConnected ? "Connected - Tap Retry" : "No Connection")
                        .font(.caption)
                        .foregroundColor(networkMonitor.isConnected ? .green : .secondary)
                }
                .padding(.bottom, 20)
                .animation(.easeInOut, value: networkMonitor.isConnected)
            }
            .navigationTitle("Offline Mode")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Row component for showing available offline features
struct OfflineFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Offline Mode") {
    struct PreviewWrapper: View {
        @State private var tab: Tab = .offline

        var body: some View {
            OfflineModeView(selectedTab: $tab)
        }
    }

    return PreviewWrapper()
}
