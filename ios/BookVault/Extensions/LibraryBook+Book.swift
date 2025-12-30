//
//  LibraryBook+Book.swift
//  BookVault
//
//  Extension to convert LibraryBook to Book for views that expect Book type.
//
//  NOTE: This file must be updated if the OpenAPI spec changes the Book or
//  LibraryBook schema. If `npm run api:generate:swift` causes compile errors
//  in this file, update the property mappings below to match the new schema.
//
//  LibraryBook = Book + addedAt (see openapi.yaml LibraryBook schema)
//

import Foundation

extension LibraryBook {
    /// Converts LibraryBook to Book (drops the addedAt field)
    /// Update this if Book/LibraryBook properties change in the OpenAPI spec.
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
