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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !detail.breadcrumb.isEmpty {
                breadcrumbView
                    .padding(.horizontal)
            }

            if !detail.childCategories.isEmpty {
                // Padded internally: the rows are full-bleed within their card, so the
                // inset belongs on the card and the heading, not on the whole section.
                subcategoriesView
            }
        }
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

    /// Full-width rows rather than a grid, matching the Categories browse list —
    /// these are the same kind of thing, and long genre names ("Relationships,
    /// Parenting & Personal Development") truncate badly in a narrow column.
    ///
    /// Built from a `VStack` with explicit separators instead of a `List`: this sits
    /// inside the detail screen's `ScrollView`, and a nested `List` gets its own
    /// scroll view and collapses to zero height.
    private var subcategoriesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subcategories")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(detail.childCategories.enumerated()), id: \.element.id) { index, child in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 50) // clears the icon, as in an inset list
                    }

                    NavigationLink(destination: CategoryDetailView(categoryId: child.id.uuidString)) {
                        CategorySummaryRow(category: child)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }
}

// MARK: - Subcategory Row

/// One subcategory as a full-width row, styled to match the Categories browse list
/// (same icon treatment, name/count stack, and trailing chevron).
private struct CategorySummaryRow: View {
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
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                Text(countLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Always shown, unlike the grid tile: in a list every row is a push, and a
            // chevron on only some rows reads as inconsistent rather than meaningful.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
