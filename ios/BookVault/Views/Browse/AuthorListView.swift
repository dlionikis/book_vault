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

// MARK: - AuthorListView_Previews

// periphery:ignore - Used by Xcode Previews
struct AuthorListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AuthorListView()
        }
        .previewDisplayName("Author List")

        NavigationView {
            AuthorListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Author List (Dark)")
    }
}
