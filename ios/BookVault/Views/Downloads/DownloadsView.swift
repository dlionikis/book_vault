//
//  DownloadsView.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 7: Offline Downloads
//

import SwiftUI

// MARK: - DownloadsView

/// Main downloads management screen
struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var storageManager = StorageManager.shared
    @State private var showingDeleteAllConfirmation = false
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            List {
                // Storage summary section
                Section {
                    StorageSummaryRow(
                        label: "Total Downloads",
                        value: StorageManager.formatFileSize(storageManager.totalSize),
                        icon: "arrow.down.circle.fill",
                        iconColor: .blue
                    )

                    StorageSummaryRow(
                        label: "Storage Limit",
                        value: StorageManager.formatFileSize(storageManager.storageLimit),
                        icon: "internaldrive.fill",
                        iconColor: .gray
                    )

                    StorageSummaryRow(
                        label: "Available Space",
                        value: StorageManager.formatFileSize(storageManager.availableDeviceSpace),
                        icon: "iphone",
                        iconColor: .green
                    )

                    // Storage usage bar
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: storageManager.storageUsagePercentage)
                            .tint(storageManager.isNearStorageLimit ? .orange : .blue)

                        Text("\(Int(storageManager.storageUsagePercentage * 100))% of limit used")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Storage")
                }

                // Active downloads section
                if !downloadManager.activeDownloads.isEmpty {
                    Section {
                        ForEach(Array(downloadManager.activeDownloads.values), id: \.id) { download in
                            ActiveDownloadRow(download: download)
                        }
                    } header: {
                        Text("Downloading")
                    }
                }

                // Downloaded books section
                if !storageManager.downloads.isEmpty {
                    Section {
                        ForEach(storageManager.downloads) { download in
                            DownloadedBookRow(download: download)
                        }
                        .onDelete(perform: deleteDownloads)
                    } header: {
                        Text("Downloaded Books (\(storageManager.downloads.count))")
                    }
                } else if downloadManager.activeDownloads.isEmpty {
                    // Empty state
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)

                            Text("No Downloads")
                                .font(.headline)

                            Text("Downloaded books will appear here for offline listening.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }

                // Settings section
                Section {
                    NavigationLink {
                        DownloadSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.gray)
                            Text("Download Settings")
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !storageManager.downloads.isEmpty {
                        Button {
                            showingDeleteAllConfirmation = true
                        } label: {
                            Text("Delete All")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete All Downloads?",
                isPresented: $showingDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    deleteAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will remove all \(storageManager.downloads.count) downloaded books from your device. You can always download them again."
                )
            }
        }
    }

    private func deleteDownloads(at offsets: IndexSet) {
        for index in offsets {
            let download = storageManager.downloads[index]
            try? storageManager.deleteDownload(bookId: download.id)
        }
    }

    private func deleteAllDownloads() {
        try? storageManager.deleteAllDownloads()
    }
}

// MARK: - StorageSummaryRow

struct StorageSummaryRow: View {
    let label: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - ActiveDownloadRow

struct ActiveDownloadRow: View {
    let download: ActiveDownload
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(download.book.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    downloadManager.cancelDownload(bookId: download.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            switch download.state {
            case .waiting:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Preparing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case let .downloading(progress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.blue)

                    HStack {
                        Text(download.formattedProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

            case let .backgroundDownloading(lastProgress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: lastProgress)
                        .tint(.blue)

                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Background download...")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(lastProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

            case let .paused(progress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.orange)

                    Text("Paused")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

            case let .failed(error):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DownloadedBookRow

struct DownloadedBookRow: View {
    let download: DownloadedBook
    @State private var showingDeleteConfirmation = false
    @StateObject private var storageManager = StorageManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Placeholder for cover image
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "book.fill")
                        .foregroundColor(.gray)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(download.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(download.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(download.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatDate(download.downloadedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Downloaded indicator
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                try? storageManager.deleteDownload(bookId: download.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Previews

#Preview {
    DownloadsView()
}
