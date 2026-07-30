//
//  AuthorListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - AuthorListView

/// List view for browsing all authors alphabetically
struct AuthorListView: View {
    var body: some View {
        BrowseListView(configuration: .authors())
    }
}
// MARK: - Previews

#Preview("Author List") {
    NavigationStack {
        AuthorListView()
    }
}

#Preview("Author List (Dark)") {
    NavigationStack {
        AuthorListView()
    }
    .preferredColorScheme(.dark)
}
