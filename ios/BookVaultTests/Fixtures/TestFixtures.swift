//
//  TestFixtures.swift
//  BookVaultTests
//
//  Centralized test data factory for creating OpenAPI-generated model instances.
//  When the OpenAPI spec changes and models are regenerated, only this file
//  needs to be updated instead of every test file.
//

import Foundation
@testable import BookVault

/// Factory methods for creating test instances of OpenAPI-generated models.
/// All methods use sensible defaults that can be overridden as needed.
enum TestFixtures {

    // MARK: - Static Test IDs (for consistent test data)

    static let testUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let testBookId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let testAuthorId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let testNarratorId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let testChapterId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    static let testRefreshToken = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    // MARK: - User

    static func makeUser(
        id: UUID = testUserId,
        email: String = "test@example.com"
    ) -> User {
        User(id: id, email: email)
    }

    // MARK: - Authentication Responses

    static func makeLoginResponse(
        accessToken: String = "test-access-token",
        refreshToken: UUID = testRefreshToken,
        user: User? = nil,
        expiresIn: Int = 3600
    ) -> LoginMobile200Response {
        LoginMobile200Response(
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: user ?? makeUser(),
            expiresIn: expiresIn
        )
    }

    static func makeRefreshTokenResponse(
        accessToken: String = "new-access-token",
        refreshToken: UUID = UUID(),
        expiresIn: Int = 3600
    ) -> RefreshToken200Response {
        RefreshToken200Response(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn
        )
    }

    // MARK: - Author

    static func makeAuthor(
        id: UUID = testAuthorId,
        name: String = "Test Author",
        asin: String? = "B00AUTHOR"
    ) -> Author {
        Author(id: id, name: name, asin: asin)
    }

    // MARK: - Narrator

    static func makeNarrator(
        id: UUID = testNarratorId,
        name: String = "Test Narrator",
        asin: String? = "B00NARRATOR"
    ) -> Narrator {
        Narrator(id: id, name: name, asin: asin)
    }

    // MARK: - Book

    static func makeBook(
        id: UUID = testBookId,
        asin: String = "B00TEST123",
        title: String = "Test Book Title",
        description: String? = "A test book description",
        runtimeMinutes: Int? = 360,
        releaseDate: Date? = nil,
        publisher: String? = "Test Publisher",
        coverUrl: String? = "/api/images/test/cover.jpg",
        audioUrl: String? = "/api/audio/test/audio.mp3",
        authors: [Author]? = nil,
        narrators: [Narrator]? = nil,
        series: [SeriesInfo]? = nil,
        categories: [BookVault.Category]? = nil
    ) -> Book {
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
            authors: authors ?? [makeAuthor()],
            narrators: narrators,
            series: series,
            categories: categories
        )
    }

    // MARK: - Chapter

    static func makeChapter(
        id: UUID = testChapterId,
        title: String = "Chapter 1",
        startTime: Double = 0.0,
        endTime: Double = 600.0,
        duration: Double = 600.0,
        index: Int = 0
    ) -> Chapter {
        Chapter(
            id: id,
            title: title,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            index: index
        )
    }

    static func makeChapterList(count: Int = 5) -> [Chapter] {
        var chapters: [Chapter] = []
        var currentTime: Double = 0
        let chapterDuration: Double = 600 // 10 minutes each

        for i in 0..<count {
            chapters.append(makeChapter(
                id: UUID(),
                title: "Chapter \(i + 1)",
                startTime: currentTime,
                endTime: currentTime + chapterDuration,
                duration: chapterDuration,
                index: i
            ))
            currentTime += chapterDuration
        }
        return chapters
    }

    // MARK: - Progress Responses

    static func makeGetProgressResponse(
        positionSeconds: Double = 0.0,
        completed: Bool = false,
        lastPlayed: Date? = nil
    ) -> GetProgress200Response {
        GetProgress200Response(
            positionSeconds: positionSeconds,
            completed: completed,
            lastPlayed: lastPlayed
        )
    }

    static func makeUpdateProgressResponse(
        positionSeconds: Double = 123.45,
        completed: Bool = false,
        lastPlayed: Date = Date(),
        updated: Bool = true
    ) -> UpdateProgress200Response {
        UpdateProgress200Response(
            positionSeconds: positionSeconds,
            completed: completed,
            lastPlayed: lastPlayed,
            updated: updated
        )
    }

    static func makeSetProgressStatusResponse(
        positionSeconds: Double = 0.0,
        completed: Bool = true,
        lastPlayed: Date? = Date()
    ) -> SetProgressStatus200Response {
        SetProgressStatus200Response(
            positionSeconds: positionSeconds,
            completed: completed,
            lastPlayed: lastPlayed
        )
    }

    // MARK: - Books List Response

    static func makePagination(
        page: Int = 1,
        limit: Int = 20,
        total: Int = 100,
        pages: Int = 5
    ) -> ListBooks200ResponsePagination {
        ListBooks200ResponsePagination(
            page: page,
            limit: limit,
            total: total,
            pages: pages
        )
    }

    static func makeListBooksResponse(
        books: [Book]? = nil,
        pagination: ListBooks200ResponsePagination? = nil
    ) -> ListBooks200Response {
        ListBooks200Response(
            books: books ?? [makeBook()],
            pagination: pagination ?? makePagination(total: books?.count ?? 1, pages: 1)
        )
    }

    // MARK: - Library Responses

    static func makeGetLibraryResponse(
        books: [Book]? = nil,
        total: Int? = nil
    ) -> GetLibrary200Response {
        let bookList = books ?? [makeBook()]
        return GetLibrary200Response(
            books: bookList,
            total: total ?? bookList.count
        )
    }

    static func makeAddToLibraryResponse(
        message: String = "Book added to library"
    ) -> AddToLibrary201Response {
        AddToLibrary201Response(message: message)
    }

    // MARK: - JSON Samples (for decoding tests)

    /// Sample JSON matching the Book schema from OpenAPI spec.
    /// Use this to test JSON decoding of generated models.
    static let bookJSON = """
    {
        "id": "22222222-2222-2222-2222-222222222222",
        "asin": "B00TEST123",
        "title": "Test Book Title",
        "description": "A test book description",
        "runtimeMinutes": 360,
        "publisher": "Test Publisher",
        "coverUrl": "/api/images/test/cover.jpg",
        "audioUrl": "/api/audio/test/audio.mp3",
        "authors": [
            {
                "id": "33333333-3333-3333-3333-333333333333",
                "name": "Test Author",
                "asin": "B00AUTHOR"
            }
        ]
    }
    """

    /// Sample JSON for login response
    static let loginResponseJSON = """
    {
        "accessToken": "test-access-token",
        "refreshToken": "66666666-6666-6666-6666-666666666666",
        "user": {
            "id": "11111111-1111-1111-1111-111111111111",
            "email": "test@example.com"
        },
        "expiresIn": 3600
    }
    """

    /// Sample JSON for progress response
    static let progressResponseJSON = """
    {
        "positionSeconds": 123.45,
        "completed": false,
        "lastPlayed": "2025-01-15T10:30:00Z"
    }
    """
}
