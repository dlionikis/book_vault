//
//  DownloadSettingsView.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 7: Offline Downloads
//

import SwiftUI

// MARK: - DownloadSettingsView

/// Settings view for download preferences
struct DownloadSettingsView: View {
    @AppStorage("downloadOnlyOnWiFi") private var wifiOnly = true
    @AppStorage("downloadStorageLimit") private var storageLimitRaw = 5_000_000_000 // 5 GB default
    @AppStorage("autoDeleteOldDownloads") private var autoDelete = false
    @AppStorage("autoDeleteDays") private var autoDeleteDays = 30

    @ObservedObject private var storageManager = StorageManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    private var storageLimit: Int64 {
        Int64(storageLimitRaw)
    }

    var body: some View {
        Form {
            // Network settings
            Section {
                Toggle("Download only on WiFi", isOn: $wifiOnly)

                // Current connection status
                HStack {
                    Text("Current Connection")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(networkMonitor.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(networkMonitor.connectionType.rawValue)
                    }
                }
            } header: {
                Text("Network")
            } footer: {
                Text("When enabled, downloads will only start when connected to WiFi to save cellular data.")
            }

            // Storage settings
            Section {
                Picker("Storage Limit", selection: $storageLimitRaw) {
                    Text("1 GB").tag(1_000_000_000)
                    Text("2 GB").tag(2_000_000_000)
                    Text("5 GB").tag(5_000_000_000)
                    Text("10 GB").tag(10_000_000_000)
                    Text("20 GB").tag(20_000_000_000)
                    Text("Unlimited").tag(Int.max)
                }

                // Current usage
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Current Usage")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(StorageManager.formatFileSize(storageManager.totalSize))
                    }

                    if storageLimitRaw != Int.max {
                        ProgressView(value: storageManager.storageUsagePercentage)
                            .tint(storageManager.isNearStorageLimit ? .orange : .blue)

                        Text(
                            "\(Int(storageManager.storageUsagePercentage * 100))% of \(StorageManager.formatFileSize(storageLimit)) used"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                // Device storage info
                HStack {
                    Text("Device Storage Available")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(StorageManager.formatFileSize(storageManager.availableDeviceSpace))
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Set a limit to prevent downloads from using too much device storage.")
            }

            // Auto-delete settings
            Section {
                Toggle("Auto-delete old downloads", isOn: $autoDelete)

                if autoDelete {
                    Picker("Delete after", selection: $autoDeleteDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                }
            } header: {
                Text("Automatic Cleanup")
            } footer: {
                if autoDelete {
                    Text(
                        "Downloads not played in \(autoDeleteDays) days will be automatically deleted to free up space."
                    )
                } else {
                    Text("Enable to automatically remove old downloads that haven't been played recently.")
                }
            }

            // Storage management
            Section {
                // Delete all downloads
                Button(role: .destructive) {
                    // This would show a confirmation dialog in the parent view
                    // For now, we'll handle it here
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All Downloads")
                    }
                }
                .disabled(storageManager.downloads.isEmpty)

                // Cleanup orphaned files
                Button {
                    storageManager.cleanupOrphanedFiles()
                } label: {
                    HStack {
                        Image(systemName: "arrow.3.trianglepath")
                        Text("Cleanup Orphaned Files")
                    }
                }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("Orphaned files are downloads that exist on disk but aren't tracked in the app's database.")
            }

            // Download statistics
            Section {
                StatRow(label: "Downloaded Books", value: "\(storageManager.downloads.count)")
                StatRow(label: "Total Size", value: StorageManager.formatFileSize(storageManager.totalSize))

                if let oldest = storageManager.downloads.min(by: { $0.downloadedAt < $1.downloadedAt }) {
                    StatRow(label: "Oldest Download", value: formatDate(oldest.downloadedAt))
                }

                if let newest = storageManager.downloads.max(by: { $0.downloadedAt < $1.downloadedAt }) {
                    StatRow(label: "Newest Download", value: formatDate(newest.downloadedAt))
                }
            } header: {
                Text("Statistics")
            }
        }
        .navigationTitle("Download Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - StatRow

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationView {
        DownloadSettingsView()
    }
}
