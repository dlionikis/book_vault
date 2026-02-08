//
//  CategoryListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - CategoryListView

/// List view for browsing all categories alphabetically
struct CategoryListView: View {
    var body: some View {
        BrowseListView(configuration: .categories())
    }
}

// MARK: - CategoryListView_Previews

// periphery:ignore - Used by Xcode Previews
struct CategoryListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CategoryListView()
        }
        .previewDisplayName("Category List")

        NavigationView {
            CategoryListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Category List (Dark)")
    }
}
