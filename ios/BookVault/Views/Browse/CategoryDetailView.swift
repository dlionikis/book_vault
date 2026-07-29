//
//  CategoryDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - CategoryDetailView

/// Detail view showing a category and all books in that category
struct CategoryDetailView: View {
    let categoryId: String

    var body: some View {
        BrowseDetailView(itemId: categoryId, configuration: .category())
    }
}

// MARK: - CategoryDetailView_Previews

// periphery:ignore - Used by Xcode Previews
struct CategoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            // Note: Using a placeholder ID for preview
            CategoryDetailView(categoryId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Category Detail")

        NavigationStack {
            CategoryDetailView(categoryId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Category Detail (Dark)")
    }
}
