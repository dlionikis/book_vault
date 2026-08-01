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

    // Observed, not owned: AuthManager is a singleton the app does not create.
    // Injected into the environment below for the view tree to consume.
    @ObservedObject private var authManager = AuthManager.shared

    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            // The app can launch or resume while the device is locked (background
            // audio, CarPlay, a push), which leaves the keychain unreadable and
            // session restoration deferred. Becoming active is the first moment
            // the tokens are guaranteed readable, so retry there — otherwise the
            // user is shown the login screen despite a perfectly valid session.
            guard newPhase == .active else { return }
            Task { await authManager.retryRestoreIfLockedOut() }
        }
    }
}
