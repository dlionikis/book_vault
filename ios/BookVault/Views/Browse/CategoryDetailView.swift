//
//  CategoryDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - CategoryDetailView

/// Detail view for a category: its place in the hierarchy, the subcategories you
/// can drill into, and the books tagged with it directly.
///
/// Categories are a tree because Audible ships each book's genre as a full ladder
/// ("SF&F > Fantasy > Epic"). The generic detail view handles the header and books;
/// the accessory below adds the parts specific to a hierarchy.
struct CategoryDetailView: View {
    let categoryId: String

    var body: some View {
        BrowseDetailView(itemId: categoryId, configuration: .category()) { detail in
            CategoryHierarchySection(detail: detail)
        }
    }
}

// MARK: - Hierarchy Section

private struct CategoryHierarchySection: View {
    let detail: GetCategory200Response

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !detail.breadcrumb.isEmpty {
                breadcrumbView
            }

            if !detail.childCategories.isEmpty {
                subcategoriesView
            }
        }
        .padding(.horizontal)
    }

    /// Ancestors as tappable chips, so you can climb back up the ladder without
    /// popping the whole navigation stack.
    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(detail.breadcrumb.enumerated()), id: \.element.id) { index, ancestor in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }

                    NavigationLink(destination: CategoryDetailView(categoryId: ancestor.id.uuidString)) {
                        Text(ancestor.name)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .accessibilityLabel("Go to \(ancestor.name)")
                }
            }
        }
    }

    private var subcategoriesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subcategories")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(detail.childCategories, id: \.id) { child in
                    NavigationLink(destination: CategoryDetailView(categoryId: child.id.uuidString)) {
                        CategorySummaryTile(category: child)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Subcategory Tile

private struct CategorySummaryTile: View {
    let category: CategorySummary

    /// A container category has no books of its own, so its own count would read
    /// "0 books" — the subtree total is the useful number. Only mention the direct
    /// tagging when it differs from the rollup.
    private var countLabel: String {
        let books = "\(category.totalBookCount) \(category.totalBookCount == 1 ? "book" : "books")"
        if category.hasChildren, category.bookCount > 0, category.bookCount < category.totalBookCount {
            return "\(books) · \(category.bookCount) directly"
        }
        return books
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(countLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            if category.hasChildren {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.name), \(countLabel)")
        .accessibilityHint(
            category.hasChildren
                ? "Tap to view books and subcategories"
                : "Tap to view books in this category"
        )
    }
}

// MARK: - Previews

#Preview("Category Detail") {
    NavigationStack {
        // Note: Using a placeholder ID for preview
        CategoryDetailView(categoryId: "00000000-0000-0000-0000-000000000000")
    }
}

#Preview("Category Detail (Dark)") {
    NavigationStack {
        CategoryDetailView(categoryId: "00000000-0000-0000-0000-000000000000")
    }
    .preferredColorScheme(.dark)
}
