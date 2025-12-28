//
//  ContentView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // User is logged in - show books list
                BooksListView()
            } else {
                // User is not logged in - show login screen
                LoginView()
            }
        }
        .animation(.default, value: authManager.isAuthenticated)
        .safeAreaInset(edge: .bottom) {
            if audioPlayer.currentBook != nil {
                MiniPlayerView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: audioPlayer.currentBook != nil)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
}
