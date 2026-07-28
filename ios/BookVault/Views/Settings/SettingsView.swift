//
//  SettingsView.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//

import SwiftUI

/// Settings screen with user preferences and account management
struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var appIconManager = AppIconManager.shared
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @ObservedObject private var playbackSettings = PlaybackSettings.shared
    @State private var showingLogoutConfirmation = false
    @State private var showingDisableBiometricConfirmation = false
    @State private var showingClearCacheConfirmation = false
    @State private var showingPlaybackSpeedPicker = false
    @State private var isLoggingOut = false

    // Cache statistics
    @State private var coverCacheStats: CoverCacheManager.CoverCacheStats?
    @State private var libraryCacheStats: LibraryCacheManager.LibraryCacheStats?
    @State private var downloadedBooksCount: Int = 0
    @State private var downloadedBooksSize: Int64 = 0

    var body: some View {
        NavigationView {
            List {
                // Appearance Section
                Section {
                    Picker("Theme", selection: $themeManager.selectedTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    if appIconManager.supportsAlternateIcons {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Icon")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack(spacing: 0) {
                                ForEach(AppIconColor.allCases) { iconColor in
                                    Button {
                                        appIconManager.selectedIcon = iconColor
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(iconColor.displayColor)
                                                .frame(width: 32, height: 32)

                                            if appIconManager.selectedIcon == iconColor {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(iconColor.rawValue) icon")
                                    .accessibilityAddTraits(
                                        appIconManager.selectedIcon == iconColor ? .isSelected : []
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose your preferred color scheme and app icon")
                }

                // Playback Section
                Section {
                    Button {
                        showingPlaybackSpeedPicker = true
                    } label: {
                        HStack {
                            Text("Default Speed")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(format: "%.2fx", playbackSettings.defaultPlaybackRate))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("New audiobooks will start at this speed")
                }

                // Security Section
                if biometricManager.canUseBiometrics {
                    Section {
                        Toggle(
                            "\(biometricManager.biometryName) Login",
                            isOn: Binding(
                                get: { biometricManager.isBiometricEnabled },
                                set: { newValue in
                                    if !newValue {
                                        showingDisableBiometricConfirmation = true
                                    }
                                    // Enable is handled via login flow, not here
                                }
                            )
                        )
                        .disabled(!biometricManager.isBiometricEnabled)

                        if !biometricManager.isBiometricEnabled {
                            Text("Log in with your password to enable \(biometricManager.biometryName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Security")
                    }
                }

                // Account Section
                Section {
                    if let username = authManager.username {
                        HStack {
                            Text("Username")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(username)
                        }
                    }

                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        HStack {
                            if isLoggingOut {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Text("Log Out")
                        }
                    }
                    .disabled(isLoggingOut)
                } header: {
                    Text("Account")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }

                // Storage Section
                Section {
                    // Cover images cache
                    if let stats = coverCacheStats {
                        DisclosureGroup {
                            if let cachedAt = stats.newestCachedAt {
                                HStack {
                                    Text("Last Cached")
                                    Spacer()
                                    Text(cachedAt, style: .relative)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if let accessed = stats.lastAccessedAt {
                                HStack {
                                    Text("Last Accessed")
                                    Spacer()
                                    Text(accessed, style: .relative)
                                        .foregroundColor(.secondary)
                                }
                            }
                            HStack {
                                Text("Total Accesses")
                                Spacer()
                                Text("\(stats.totalAccessCount)")
                                    .foregroundColor(.secondary)
                            }
                        } label: {
                            HStack {
                                Label("Cover Images", systemImage: "photo.stack")
                                Spacer()
                                Text("\(stats.count) (\(formatBytes(stats.totalSize)))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Library cache
                    if let stats = libraryCacheStats {
                        DisclosureGroup {
                            if let createdAt = stats.createdAt {
                                HStack {
                                    Text("Created")
                                    Spacer()
                                    Text(createdAt, style: .relative)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if let syncDate = stats.lastSyncDate {
                                HStack {
                                    Text("Last Synced")
                                    Spacer()
                                    Text(syncDate, style: .relative)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if let accessed = stats.lastAccessedAt {
                                HStack {
                                    Text("Last Accessed")
                                    Spacer()
                                    Text(accessed, style: .relative)
                                        .foregroundColor(.secondary)
                                }
                            }
                            HStack {
                                Text("Access Count")
                                Spacer()
                                Text("\(stats.accessCount)")
                                    .foregroundColor(.secondary)
                            }
                        } label: {
                            HStack {
                                Label("Library Cache", systemImage: "books.vertical")
                                Spacer()
                                if stats.bookCount > 0 {
                                    Text("\(stats.bookCount) books")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Empty")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Downloaded audiobooks
                    HStack {
                        Label("Downloaded Books", systemImage: "arrow.down.circle.fill")
                        Spacer()
                        Text("\(downloadedBooksCount) books (\(formatBytes(downloadedBooksSize)))")
                            .foregroundColor(.secondary)
                    }

                    // Clear cache button
                    Button(role: .destructive) {
                        showingClearCacheConfirmation = true
                    } label: {
                        Label("Clear Cover Cache", systemImage: "trash")
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Cover images are cached locally for faster loading. Access counts show cache usage.")
                }
            }
            .onAppear {
                refreshCacheStats()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("Log Out", isPresented: $showingLogoutConfirmation) {
                Button("Log Out", role: .destructive) {
                    Task {
                        isLoggingOut = true
                        await authManager.logout()
                        isLoggingOut = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
            .confirmationDialog(
                "Disable \(biometricManager.biometryName)?",
                isPresented: $showingDisableBiometricConfirmation
            ) {
                Button("Disable", role: .destructive) {
                    biometricManager.disableBiometric()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your password to log in")
            }
            .confirmationDialog(
                "Clear Cover Cache?",
                isPresented: $showingClearCacheConfirmation
            ) {
                Button("Clear Cache", role: .destructive) {
                    CoverCacheManager.shared.clearCache()
                    refreshCacheStats()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let stats = coverCacheStats {
                    Text("This will remove \(stats.count) cached cover images (\(formatBytes(stats.totalSize))). They will be re-downloaded as needed.")
                } else {
                    Text("This will clear all cached cover images.")
                }
            }
            .sheet(isPresented: $showingPlaybackSpeedPicker) {
                PlaybackSpeedPicker(
                    currentRate: playbackSettings.defaultPlaybackRate
                ) { selectedRate in
                    playbackSettings.defaultPlaybackRate = selectedRate
                    showingPlaybackSpeedPicker = false
                }
            }
        }
    }

    // MARK: - Private Methods

    private func refreshCacheStats() {
        // Cover cache stats
        coverCacheStats = CoverCacheManager.shared.getCacheStats()

        // Library cache stats (use getCacheStats to avoid incrementing access count)
        libraryCacheStats = LibraryCacheManager.shared.getCacheStats()

        // Downloaded books stats
        let downloadStats = DownloadManager.shared.getStorageStats()
        downloadedBooksCount = downloadStats.count
        downloadedBooksSize = downloadStats.size
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environmentObject(AuthManager.shared)
}

#Preview("Settings (Dark)") {
    SettingsView()
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
