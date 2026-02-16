//
//  APIClientRealTests.swift
//  BookVaultTests
//
//  Phase 4: Real service tests for APIClient.
//  Tests actual API logic with URLProtocol interception.
//

import XCTest
@testable import BookVault

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    // Handler to provide mock responses
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // Track all requests made
    static var capturedRequests: [URLRequest] = []

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(
                domain: "MockURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nothing to do
    }

    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }
}

// MARK: - APIClientRealTests

final class APIClientRealTests: XCTestCase {
    var sut: APIClient!
    var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        // Create URLSession with mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Create APIClient with mock session
        let baseURL = URL(string: "http://localhost:3000")!
        sut = APIClient(baseURL: baseURL, session: mockSession)

        // Disable force logout for tests
        sut.forceLogoutHandler = {}
    }

    override func tearDown() {
        MockURLProtocol.reset()
        sut = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    func makeJSONResponse(statusCode: Int, json: [String: Any]) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://localhost:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (response, data)
    }

    func makeJSONResponse(statusCode: Int, object: some Encodable) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://localhost:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(object)
        return (response, data)
    }

    // MARK: - Initialization Tests

    func testInitializationSetsBaseURL() {
        XCTAssertEqual(sut.baseURL.absoluteString, "http://localhost:3000")
    }

    func testInitialAccessTokenIsNil() {
        XCTAssertNil(sut.accessToken)
    }

    // MARK: - Login Tests

    func testLoginSuccess() async throws {
        // Given
        let userId = UUID()
        let refreshToken = UUID()
        let responseJSON: [String: Any] = [
            "user": [
                "id": userId.uuidString,
                "username": "testuser"
            ],
            "accessToken": "test-access-token",
            "refreshToken": refreshToken.uuidString,
            "expiresIn": 3600
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/mobile/login")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        let response = try await sut.login(username: "testuser", password: "password123")

        // Then
        XCTAssertEqual(response.user.username, "testuser")
        XCTAssertEqual(response.accessToken, "test-access-token")
        XCTAssertEqual(sut.accessToken, "test-access-token") // Should be stored
    }

    func testLoginSendsCorrectRequestBody() async throws {
        // Given
        let userId = UUID()
        let refreshToken = UUID()
        let responseJSON: [String: Any] = [
            "user": [
                "id": userId.uuidString,
                "username": "testuser"
            ],
            "accessToken": "token",
            "refreshToken": refreshToken.uuidString,
            "expiresIn": 3600
        ]

        var capturedBody: [String: String]?

        MockURLProtocol.requestHandler = { request in
            // httpBody can be nil in URLProtocol - try httpBodyStream instead
            if let bodyData = request.httpBody {
                capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String]
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let bytesRead = stream.read(buffer, maxLength: bufferSize)
                    if bytesRead > 0 {
                        data.append(buffer, count: bytesRead)
                    }
                }
                stream.close()
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            }
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        _ = try await sut.login(username: "testuser2", password: "secret123")

        // Then
        XCTAssertEqual(capturedBody?["username"], "testuser2")
        XCTAssertEqual(capturedBody?["password"], "secret123")
    }

    func testLoginUnauthorizedError() async {
        // Given
        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 401, json: ["error": "Invalid credentials"])
        }

        // When/Then
        do {
            _ = try await sut.login(username: "testuser", password: "wrong")
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            if case .unauthorized = error {
                // Expected
            } else {
                XCTFail("Expected unauthorized error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Token Refresh Tests

    func testRefreshTokenSuccess() async throws {
        // Given
        sut.accessToken = "old-token"
        let refreshToken = UUID()
        let newRefreshToken = UUID()
        let responseJSON: [String: Any] = [
            "accessToken": "new-access-token",
            "refreshToken": newRefreshToken.uuidString,
            "expiresIn": 3600
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/mobile/refresh")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        let response = try await sut.refreshToken(refreshToken: refreshToken)

        // Then
        XCTAssertEqual(response.accessToken, "new-access-token")
        XCTAssertEqual(sut.accessToken, "new-access-token") // Should be updated
    }

    // MARK: - Fetch Books Tests

    func testFetchBooksSuccess() async throws {
        // Given
        sut.accessToken = "valid-token"
        let bookId = UUID()
        let authorId = UUID()
        let responseJSON: [String: Any] = [
            "books": [
                [
                    "id": bookId.uuidString,
                    "asin": "B001234",
                    "title": "Test Book",
                    "authors": [["id": authorId.uuidString, "name": "Author Name", "asin": "A123"]],
                    "narrators": [],
                    "description": "A test book",
                    "runtimeMinutes": 300,
                    "releaseDate": "2024-01-01"
                ]
            ],
            "pagination": [
                "page": 1,
                "limit": 20,
                "total": 1,
                "pages": 1
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/books") ?? false)
            XCTAssertEqual(request.httpMethod, "GET")
            // Verify auth header
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-token")
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        let response = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)

        // Then
        XCTAssertEqual(response.books.count, 1)
        XCTAssertEqual(response.books.first?.title, "Test Book")
        XCTAssertEqual(response.pagination.total, 1)
    }

    func testFetchBooksWithPagination() async throws {
        // Given
        sut.accessToken = "valid-token"
        let responseJSON: [String: Any] = [
            "books": [],
            "pagination": ["page": 2, "limit": 10, "total": 50, "pages": 5]
        ]

        var capturedURL: URL?

        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        _ = try await sut.fetchBooks(page: 2, limit: 10, sortBy: "title")

        // Then
        XCTAssertNotNil(capturedURL)
        let components = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems

        XCTAssertTrue(queryItems?.contains(where: { $0.name == "page" && $0.value == "2" }) ?? false)
        XCTAssertTrue(queryItems?.contains(where: { $0.name == "limit" && $0.value == "10" }) ?? false)
        XCTAssertTrue(queryItems?.contains(where: { $0.name == "sortBy" && $0.value == "title" }) ?? false)
    }

    // MARK: - Fetch Single Book Tests

    func testFetchBookSuccess() async throws {
        // Given
        sut.accessToken = "valid-token"
        let bookId = UUID()
        let authorId = UUID()
        let responseJSON: [String: Any] = [
            "id": bookId.uuidString,
            "asin": "B001234",
            "title": "Single Book",
            "authors": [["id": authorId.uuidString, "name": "Author", "asin": "A123"]],
            "narrators": [],
            "description": "Description",
            "runtimeMinutes": 200,
            "releaseDate": "2024-01-01"
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains(bookId.uuidString) ?? false)
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        let book = try await sut.fetchBook(id: bookId)

        // Then
        XCTAssertEqual(book.id, bookId)
        XCTAssertEqual(book.title, "Single Book")
    }

    func testFetchBookNotFound() async {
        // Given
        sut.accessToken = "valid-token"

        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 404, json: ["error": "Not found"])
        }

        // When/Then
        do {
            _ = try await sut.fetchBook(id: UUID())
            XCTFail("Expected notFound error")
        } catch let error as APIError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected notFound error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Progress Tests

    func testUpdateProgressSuccess() async throws {
        // Given
        sut.accessToken = "valid-token"
        let bookId = UUID()
        let dateFormatter = ISO8601DateFormatter()
        let lastPlayed = dateFormatter.string(from: Date())
        let responseJSON: [String: Any] = [
            "positionSeconds": 123.45,
            "completed": false,
            "lastPlayed": lastPlayed,
            "updated": true
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/progress")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        let response = try await sut.updateProgress(bookId: bookId, positionSeconds: 123.45)

        // Then
        XCTAssertTrue(response.updated)
        XCTAssertEqual(response.positionSeconds, 123.45)
    }

    // MARK: - Error Handling Tests

    func testServerErrorHandling() async {
        // Given
        sut.accessToken = "valid-token"

        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 500, json: ["error": "Internal server error"])
        }

        // When/Then
        do {
            _ = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)
            XCTFail("Expected server error")
        } catch let error as APIError {
            if case let .serverError(code, message) = error {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(message, "Internal server error")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkErrorHandling() async {
        // Given
        sut.accessToken = "valid-token"

        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }

        // When/Then
        do {
            _ = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)
            XCTFail("Expected network error")
        } catch {
            // Expected - any error is fine, network errors are wrapped
        }
    }

    // MARK: - Authorization Header Tests

    func testAuthorizationHeaderIncludedWhenTokenSet() async throws {
        // Given
        sut.accessToken = "my-auth-token"
        let responseJSON: [String: Any] = [
            "books": [],
            "pagination": ["page": 1, "limit": 20, "total": 0, "pages": 0]
        ]

        var capturedAuthHeader: String?

        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        _ = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)

        // Then
        XCTAssertEqual(capturedAuthHeader, "Bearer my-auth-token")
    }

    // MARK: - Content Type Tests

    func testRequestIncludesCorrectContentType() async throws {
        // Given
        sut.accessToken = "token"
        let userId = UUID()
        let refreshToken = UUID()
        let responseJSON: [String: Any] = [
            "user": ["id": userId.uuidString, "username": "testuser"],
            "accessToken": "token",
            "refreshToken": refreshToken.uuidString,
            "expiresIn": 3600
        ]

        var capturedContentType: String?

        MockURLProtocol.requestHandler = { request in
            capturedContentType = request.value(forHTTPHeaderField: "Content-Type")
            return self.makeJSONResponse(statusCode: 200, json: responseJSON)
        }

        // When
        _ = try await sut.login(username: "testuser", password: "password")

        // Then
        XCTAssertEqual(capturedContentType, "application/json")
    }

    // MARK: - Logout Tests

    func testLogoutClearsAccessToken() async throws {
        // Given
        sut.accessToken = "my-token"

        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 200, json: ["message": "Logged out successfully"])
        }

        // When
        try await sut.logout(refreshToken: UUID())

        // Then
        XCTAssertNil(sut.accessToken)
    }
}
