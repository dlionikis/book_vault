//
//  LibraryBook+Book.swift
//  BookVault
//
//  Extension to convert LibraryBook to Book for views that expect Book type.
//

import Foundation

extension LibraryBook {
    /// Converts LibraryBook to Book (drops the addedAt field)
    var asBook: Book {
        Book(
            id: id,
            asin: asin,
            title: title,
            description: description,
            runtimeMinutes: runtimeMinutes,
            releaseDate: releaseDate,
            publisher: publisher,
            coverUrl: coverUrl,
            audioUrl: audioUrl,
            authors: authors,
            narrators: narrators,
            series: series,
            categories: categories
        )
    }
}
