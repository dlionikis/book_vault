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
// MARK: - Previews

#Preview("Category List") {
    NavigationStack {
        CategoryListView()
    }
}

#Preview("Category List (Dark)") {
    NavigationStack {
        CategoryListView()
    }
    .preferredColorScheme(.dark)
}
