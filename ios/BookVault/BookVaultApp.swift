//
//  BookVaultApp.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

@main
struct BookVaultApp: App {
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
