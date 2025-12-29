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
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingLogoutConfirmation = false
    @State private var isLoggingOut = false

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
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose your preferred color scheme")
                }

                // Account Section
                Section {
                    if let email = authManager.userEmail {
                        HStack {
                            Text("Email")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(email)
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
        }
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
