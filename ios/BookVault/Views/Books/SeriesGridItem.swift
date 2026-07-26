//
//  SeriesGridItem.swift
//  BookVault
//
//  Series-mode grid tile for Catalog/Library — the series counterpart to
//  BookGridItem (CatalogView.swift). See
//  docs/plans/series-view-toggle-implementation.md, "SeriesGridItem (iOS)".
//

import SwiftUI

/// A `CatalogSeriesViewItem` always has exactly one of `series`/`book` set
/// (enforced server-side, see the generated model's doc comment) — this id
/// lets `ForEach` identify rows without either field being a required,
/// always-present key.
extension CatalogSeriesViewItem: Identifiable {
    public var id: String {
        if let series { return "series-\(series.id.uuidString)" }
        if let book { return "book-\(book.id.uuidString)" }
        return UUID().uuidString
    }
}

struct SeriesGridItem: View {
    let series: SeriesWithBookCount

    /// Internal rather than private so the ownership phrasing can be unit-tested
    /// directly (see `SeriesGridItemOwnershipTests`).
    var bookCountLabel: String {
        if let ownedCount = series.ownedCount, ownedCount < series.bookCount {
            return "\(ownedCount) of \(series.bookCount) in your library"
        }
        let count = series.bookCount
        return "\(count) book\(count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedCoverImage(bookId: series.id, coverUrl: series.coverUrl)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(series.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text(bookCountLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Previews

#Preview("Series Grid Item") {
    NavigationView {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 20) {
                SeriesGridItem(series: SeriesWithBookCount(
                    id: UUID(),
                    title: "The Kingkiller Chronicle",
                    asin: nil,
                    bookCount: 3
                ))
                SeriesGridItem(series: SeriesWithBookCount(
                    id: UUID(),
                    title: "A Series With a Very Long Name That Wraps",
                    asin: nil,
                    bookCount: 1
                ))
                SeriesGridItem(series: SeriesWithBookCount(
                    id: UUID(),
                    title: "Partially Owned Series",
                    asin: nil,
                    bookCount: 5,
                    ownedCount: 2
                ))
            }
            .padding()
        }
        .navigationTitle("Catalog")
    }
}
