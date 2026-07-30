//
//  AuthorDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - AuthorDetailView

/// Detail view showing an author and all their books
struct AuthorDetailView: View {
    let authorId: String

    var body: some View {
        BrowseDetailView(itemId: authorId, configuration: .author())
    }
}
// MARK: - Previews

#Preview("Author Detail") {
    NavigationStack {
        // Note: Using a placeholder ID for preview
        AuthorDetailView(authorId: "00000000-0000-0000-0000-000000000000")
    }
}

#Preview("Author Detail (Dark)") {
    NavigationStack {
        AuthorDetailView(authorId: "00000000-0000-0000-0000-000000000000")
    }
    .preferredColorScheme(.dark)
}
