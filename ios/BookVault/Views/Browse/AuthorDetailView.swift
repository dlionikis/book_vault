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

// MARK: - AuthorDetailView_Previews

// periphery:ignore - Used by Xcode Previews
struct AuthorDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            // Note: Using a placeholder ID for preview
            AuthorDetailView(authorId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Author Detail")

        NavigationView {
            AuthorDetailView(authorId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Author Detail (Dark)")
    }
}
