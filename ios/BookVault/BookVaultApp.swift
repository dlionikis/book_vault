//
//  BookVaultApp.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

@main
struct BookVaultApp: App {
    // AppDelegate for handling background URLSession events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authManager = AuthManager.shared

    init() {
        // Phase 8: Start background sync monitoring
        // This ensures progress is synced when connectivity returns
        Task { @MainActor in
            SyncManager.shared.startMonitoring()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
