//
//  ModelDecodingTests.swift
//  BookVaultTests
//
//  Tests that validate JSON decoding of OpenAPI-generated models.
//  These tests ensure the generated models correctly decode API responses.
//

import XCTest
@testable import BookVault

final class ModelDecodingTests: XCTestCase {

    var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        // Configure decoder to match APIClient's date handling
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try date-only format
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - Book Decoding Tests

    func testDecodesBookFromJSON() throws {
        let data = TestFixtures.bookJSON.data(using: .utf8)!

        let book = try decoder.decode(Book.self, from: data)

        XCTAssertEqual(book.id, TestFixtures.testBookId)
        XCTAssertEqual(book.asin, "B00TEST123")
        XCTAssertEqual(book.title, "Test Book Title")
        XCTAssertEqual(book.description, "A test book description")
        XCTAssertEqual(book.runtimeMinutes, 360)
        XCTAssertEqual(book.publisher, "Test Publisher")
        XCTAssertEqual(book.authors.count, 1)
        XCTAssertEqual(book.authors.first?.name, "Test Author")
    }

    func testDecodesBookWithMinimalFields() throws {
        // Book with only required fields
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "asin": "B00MINIMAL",
            "title": "Minimal Book",
            "authors": []
        }
        """
        let data = json.data(using: .utf8)!

        let book = try decoder.decode(Book.self, from: data)

        XCTAssertEqual(book.title, "Minimal Book")
        XCTAssertNil(book.description)
        XCTAssertNil(book.runtimeMinutes)
        XCTAssertTrue(book.authors.isEmpty)
    }

    // MARK: - Login Response Decoding Tests

    func testDecodesLoginResponseFromJSON() throws {
        let data = TestFixtures.loginResponseJSON.data(using: .utf8)!

        let response = try decoder.decode(LoginMobile200Response.self, from: data)

        XCTAssertEqual(response.accessToken, "test-access-token")
        XCTAssertEqual(response.refreshToken, TestFixtures.testRefreshToken)
        XCTAssertEqual(response.user.id, TestFixtures.testUserId)
        XCTAssertEqual(response.user.email, "test@example.com")
        XCTAssertEqual(response.expiresIn, 3600)
    }

    // MARK: - Progress Response Decoding Tests

    func testDecodesProgressResponseFromJSON() throws {
        let data = TestFixtures.progressResponseJSON.data(using: .utf8)!

        let response = try decoder.decode(GetProgress200Response.self, from: data)

        XCTAssertEqual(response.positionSeconds, 123.45)
        XCTAssertFalse(response.completed)
        XCTAssertNotNil(response.lastPlayed)
    }

    func testDecodesProgressWithNullLastPlayed() throws {
        let json = """
        {
            "positionSeconds": 0,
            "completed": false,
            "lastPlayed": null
        }
        """
        let data = json.data(using: .utf8)!

        let response = try decoder.decode(GetProgress200Response.self, from: data)

        XCTAssertEqual(response.positionSeconds, 0)
        XCTAssertFalse(response.completed)
        XCTAssertNil(response.lastPlayed)
    }

    // MARK: - Date Format Tests

    func testDecodesISO8601DateWithFractionalSeconds() throws {
        let json = """
        {
            "positionSeconds": 100,
            "completed": false,
            "lastPlayed": "2025-12-28T19:07:21.367Z"
        }
        """
        let data = json.data(using: .utf8)!

        let response = try decoder.decode(GetProgress200Response.self, from: data)

        XCTAssertNotNil(response.lastPlayed)
    }

    func testDecodesISO8601DateWithoutFractionalSeconds() throws {
        let json = """
        {
            "positionSeconds": 100,
            "completed": false,
            "lastPlayed": "2025-12-28T19:07:21Z"
        }
        """
        let data = json.data(using: .utf8)!

        let response = try decoder.decode(GetProgress200Response.self, from: data)

        XCTAssertNotNil(response.lastPlayed)
    }

    // MARK: - Chapter Decoding Tests

    func testDecodesChapterFromJSON() throws {
        let json = """
        {
            "id": "55555555-5555-5555-5555-555555555555",
            "title": "Chapter 1: Introduction",
            "startTime": 0.0,
            "endTime": 600.5,
            "duration": 600.5,
            "index": 0
        }
        """
        let data = json.data(using: .utf8)!

        let chapter = try decoder.decode(Chapter.self, from: data)

        XCTAssertEqual(chapter.id, TestFixtures.testChapterId)
        XCTAssertEqual(chapter.title, "Chapter 1: Introduction")
        XCTAssertEqual(chapter.startTime, 0.0)
        XCTAssertEqual(chapter.endTime, 600.5)
        XCTAssertEqual(chapter.duration, 600.5)
        XCTAssertEqual(chapter.index, 0)
    }

    // MARK: - User Decoding Tests

    func testDecodesUserFromJSON() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "email": "user@example.com"
        }
        """
        let data = json.data(using: .utf8)!

        let user = try decoder.decode(User.self, from: data)

        XCTAssertEqual(user.id, TestFixtures.testUserId)
        XCTAssertEqual(user.email, "user@example.com")
    }

    // MARK: - List Response Decoding Tests

    func testDecodesListBooksResponseFromJSON() throws {
        let json = """
        {
            "books": [
                {
                    "id": "22222222-2222-2222-2222-222222222222",
                    "asin": "B001",
                    "title": "Book 1",
                    "authors": []
                }
            ],
            "pagination": {
                "page": 1,
                "limit": 20,
                "total": 1,
                "pages": 1
            }
        }
        """
        let data = json.data(using: .utf8)!

        let response = try decoder.decode(ListBooks200Response.self, from: data)

        XCTAssertEqual(response.books.count, 1)
        XCTAssertEqual(response.books.first?.title, "Book 1")
        XCTAssertEqual(response.pagination.page, 1)
        XCTAssertEqual(response.pagination.total, 1)
    }

    // MARK: - Error Cases

    func testThrowsOnMissingRequiredField() {
        // Book missing required 'title' field
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "asin": "B00TEST",
            "authors": []
        }
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(Book.self, from: data)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                XCTFail("Expected keyNotFound error, got \(error)")
                return
            }
            XCTAssertEqual(key.stringValue, "title")
        }
    }

    func testThrowsOnInvalidUUID() {
        let json = """
        {
            "id": "not-a-valid-uuid",
            "asin": "B00TEST",
            "title": "Test",
            "authors": []
        }
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(Book.self, from: data))
    }
}
