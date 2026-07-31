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
    // Handler to provide mock responses.
    //
    // Lock-backed: URLProtocol callbacks run on URLSession's queues, so these
    // really are read from a different thread than the test body that writes
    // them. Under the Swift 6 language mode a plain `static var` is rejected,
    // and correctly so. The computed-property wrappers keep every existing call
    // site (`MockURLProtocol.requestHandler = { ... }`) working unchanged.
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { requestHandlerStorage.value }
        set { requestHandlerStorage.value = newValue }
    }

    private static let requestHandlerStorage =
        Locked<(@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)

    // Track all requests made
    static var capturedRequests: [URLRequest] {
        get { capturedRequestsStorage.value }
        set { capturedRequestsStorage.value = newValue }
    }

    fileprivate static let capturedRequestsStorage = Locked<[URLRequest]>([])

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // withLock, not `capturedRequests.append(...)`: the latter takes the
        // lock once to read and again to write, letting a concurrent request
        // slip in between and get lost.
        MockURLProtocol.capturedRequestsStorage.withLock { $0.append(request) }

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

/// `@unchecked Sendable` so test bodies can capture `self` in the `@Sendable`
/// URLProtocol handlers. XCTest runs one instance per test method, never
/// concurrently, so there is no cross-test state to race on.
final class APIClientRealTests: XCTestCase, @unchecked Sendable {
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

    // `nonisolated`: pure builders, called from the @Sendable URLProtocol handlers.
    /// Pre-serialize a JSON dictionary so it can cross into a `@Sendable`
    /// URLProtocol handler. `[String: Any]` is not `Sendable`; `Data` is.
    nonisolated func jsonData(_ json: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: json)
    }

    nonisolated func makeResponse(statusCode: Int, data: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://localhost:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    nonisolated func makeJSONResponse(statusCode: Int, json: [String: Any]) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://localhost:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (response, data)
    }

    nonisolated func makeJSONResponse(statusCode: Int, object: some Encodable) -> (HTTPURLResponse, Data) {
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
        let responseData = jsonData(responseJSON)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/mobile/login")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeResponse(statusCode: 200, data: responseData)
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
        let responseData = jsonData(responseJSON)

        let capturedBody = Locked<[String: String]?>(nil)

        MockURLProtocol.requestHandler = { request in
            // httpBody can be nil in URLProtocol - try httpBodyStream instead
            if let bodyData = request.httpBody {
                capturedBody.value = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String]
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
                capturedBody.value = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            }
            return self.makeResponse(statusCode: 200, data: responseData)
        }

        // When
        _ = try await sut.login(username: "testuser2", password: "secret123")

        // Then
        XCTAssertEqual(capturedBody.value?["username"], "testuser2")
        XCTAssertEqual(capturedBody.value?["password"], "secret123")
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
        let responseData = jsonData(responseJSON)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/mobile/refresh")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeResponse(statusCode: 200, data: responseData)
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
        let responseData = jsonData(responseJSON)

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/books") ?? false)
            XCTAssertEqual(request.httpMethod, "GET")
            // Verify auth header
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-token")
            return self.makeResponse(statusCode: 200, data: responseData)
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
        let responseData = jsonData(responseJSON)

        let capturedURL = Locked<URL?>(nil)

        MockURLProtocol.requestHandler = { request in
            capturedURL.value = request.url
            return self.makeResponse(statusCode: 200, data: responseData)
        }

        // When
        _ = try await sut.fetchBooks(page: 2, limit: 10, sortBy: "title")

        // Then
        XCTAssertNotNil(capturedURL.value)
        let components = URLComponents(url: capturedURL.value!, resolvingAgainstBaseURL: false)
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
        let responseData = jsonData(responseJSON)

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains(bookId.uuidString) ?? false)
            return self.makeResponse(statusCode: 200, data: responseData)
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
        let responseData = jsonData(responseJSON)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/progress")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeResponse(statusCode: 200, data: responseData)
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
        let responseData = jsonData(responseJSON)

        let capturedAuthHeader = Locked<String?>(nil)

        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader.value = request.value(forHTTPHeaderField: "Authorization")
            return self.makeResponse(statusCode: 200, data: responseData)
        }

        // When
        _ = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)

        // Then
        XCTAssertEqual(capturedAuthHeader.value, "Bearer my-auth-token")
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
        let responseData = jsonData(responseJSON)

        let capturedContentType = Locked<String?>(nil)

        MockURLProtocol.requestHandler = { request in
            capturedContentType.value = request.value(forHTTPHeaderField: "Content-Type")
            return self.makeResponse(statusCode: 200, data: responseData)
        }

        // When
        _ = try await sut.login(username: "testuser", password: "password")

        // Then
        XCTAssertEqual(capturedContentType.value, "application/json")
    }

    // Ported from the former APIClientTests placeholder stub (Phase 1 cleanup):
    // when no access token is set, requests must NOT carry an Authorization header.
    func testUnauthenticatedRequestOmitsAuthorizationHeader() async throws {
        // Given: no access token set (sut starts with nil token from setUp)
        XCTAssertNil(sut.accessToken)
        let responseJSON: [String: Any] = [
            "books": [],
            "pagination": ["page": 1, "limit": 20, "total": 0, "pages": 0]
        ]
        let responseData = jsonData(responseJSON)

        let capturedAuthHeader = Locked<String?>("sentinel")
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader.value = request.value(forHTTPHeaderField: "Authorization")
            return self.makeResponse(statusCode: 200, data: responseData)
        }

        // When
        _ = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)

        // Then
        XCTAssertNil(capturedAuthHeader.value, "No Authorization header should be sent without a token")
    }

    // Ported from the former APIClientTests placeholder stub (Phase 1 cleanup):
    // malformed JSON in a 200 response surfaces as APIError.decodingError.
    func testMalformedJSONThrowsDecodingError() async {
        // Given
        sut.accessToken = "valid-token"

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://localhost:3000")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            // Not valid JSON for the expected model
            let data = Data("{ this is not valid json".utf8)
            return (response, data)
        }

        // When/Then
        do {
            _ = try await sut.fetchBooks(page: 1, limit: 20, sortBy: nil)
            XCTFail("Expected decodingError")
        } catch let error as APIError {
            if case .decodingError = error {
                // Expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    // MARK: - Download Endpoint Tests

    func testCheckDownloadEligibilitySuccess() async throws {
        // Given
        sut.accessToken = "download-token"
        let bookId = UUID()

        let capturedAuthHeader = Locked<String?>(nil)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/downloads/\(bookId.uuidString)/check")
            XCTAssertEqual(request.httpMethod, "GET")
            capturedAuthHeader.value = request.value(forHTTPHeaderField: "Authorization")
            return self.makeJSONResponse(statusCode: 200, json: ["eligible": true])
        }

        // When
        let response = try await sut.checkDownloadEligibility(bookId: bookId)

        // Then
        XCTAssertTrue(response.eligible)
        XCTAssertEqual(capturedAuthHeader.value, "Bearer download-token")
    }

    func testGenerateDownloadUrlSendsDeviceIdAndDecodesResponse() async throws {
        // Given
        sut.accessToken = "download-token"
        let bookId = UUID()
        let responseJSON: [String: Any] = [
            "downloadUrl": "https://s3.example.com/audiobooks/test.mp3?signature=abc",
            "expiresAt": "2026-01-01T00:00:00Z",
            "fileSize": 12_345_678
        ]
        let responseData = jsonData(responseJSON)

        let capturedBody = Locked<[String: String]?>(nil)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/downloads/\(bookId.uuidString)")
            XCTAssertEqual(request.httpMethod, "POST")
            // httpBody can be nil in URLProtocol - try httpBodyStream instead
            if let bodyData = request.httpBody {
                capturedBody.value = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String]
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
                capturedBody.value = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            }
            return self.makeResponse(statusCode: 200, data: responseData)
        }

        // When
        let result = try await sut.generateDownloadUrl(bookId: bookId, deviceId: "test-device-id")

        // Then — a 200 decodes to .ready with the presigned URL
        XCTAssertEqual(capturedBody.value?["deviceId"], "test-device-id")
        guard case let .ready(response) = result else {
            return XCTFail("Expected .ready, got \(result)")
        }
        XCTAssertEqual(response.downloadUrl, "https://s3.example.com/audiobooks/test.mp3?signature=abc")
        XCTAssertEqual(response.fileSize, 12_345_678)
    }

    func testGenerateDownloadUrlServerError() async {
        // Given
        sut.accessToken = "download-token"

        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 501, json: ["error": "S3 not configured"])
        }

        // When/Then
        do {
            _ = try await sut.generateDownloadUrl(bookId: UUID(), deviceId: nil)
            XCTFail("Expected serverError")
        } catch let error as APIError {
            if case let .serverError(code, message) = error {
                XCTAssertEqual(code, 501)
                XCTAssertEqual(message, "S3 not configured")
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Restore / Archive Tests

    func testGenerateDownloadUrlRestoringDecodes202() async throws {
        // Given — an archived file returns 202 with a BookStreamResponse body
        sut.accessToken = "download-token"
        let eta = Date().addingTimeInterval(5 * 3600)
        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 202, object: BookStreamResponse(
                status: .restoring,
                bookId: UUID(),
                message: "Restore in progress",
                estimatedCompletion: eta
            ))
        }

        // When
        let result = try await sut.generateDownloadUrl(bookId: UUID(), deviceId: nil)

        // Then — the 202 body decodes as .restoring, not a decode failure
        guard case let .restoring(restore) = result else {
            return XCTFail("Expected .restoring, got \(result)")
        }
        XCTAssertEqual(restore.status, .restoring)
        XCTAssertEqual(restore.message, "Restore in progress")
    }

    func testRestoreBookReturnsRestoringOn202() async throws {
        // Given
        sut.accessToken = "token"
        let bookId = UUID()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/books/\(bookId.uuidString)/restore")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeJSONResponse(statusCode: 202, object: BookStreamResponse(
                status: .restoring,
                message: "Restore initiated"
            ))
        }

        // When
        let response = try await sut.restoreBook(bookId: bookId)

        // Then
        XCTAssertEqual(response.status, .restoring)
    }

    func testRestoreBookReturnsAvailableOn200() async throws {
        // Given — file wasn't actually archived; endpoint self-heals to 200
        sut.accessToken = "token"
        MockURLProtocol.requestHandler = { _ in
            self.makeJSONResponse(statusCode: 200, object: BookStreamResponse(
                status: .available,
                streamUrl: "https://s3.example.com/audio.m4b"
            ))
        }

        // When
        let response = try await sut.restoreBook(bookId: UUID())

        // Then
        XCTAssertEqual(response.status, .available)
        XCTAssertNotNil(response.streamUrl)
    }

    func testGetBookRestoreStatusDecodes() async throws {
        // Given
        sut.accessToken = "token"
        let bookId = UUID()
        let eta = Date().addingTimeInterval(3 * 3600)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/books/\(bookId.uuidString)/restore-status")
            return self.makeJSONResponse(statusCode: 200, object: RestoreStatus(
                status: .restoring,
                estimatedCompletion: eta
            ))
        }

        // When
        let status = try await sut.getBookRestoreStatus(bookId: bookId)

        // Then
        XCTAssertEqual(status.status, .restoring)
        XCTAssertNotNil(status.estimatedCompletion)
    }

    func testListRestoresDecodes() async throws {
        // Given
        sut.accessToken = "token"
        let summary = RestoreRequestSummary(
            id: UUID(),
            bookId: UUID(),
            status: .inProgress,
            requestedAt: Date(),
            book: RestoreRequestSummaryBook(id: UUID(), title: "Test Book")
        )
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/books/restores")
            return self.makeJSONResponse(statusCode: 200, object: RestoresListResponse(restores: [summary]))
        }

        // When
        let response = try await sut.listRestores()

        // Then
        XCTAssertEqual(response.restores.count, 1)
        XCTAssertEqual(response.restores.first?.book.title, "Test Book")
    }

    func testRestoreSeriesDecodes() async throws {
        // Given
        sut.accessToken = "token"
        let seriesId = UUID()
        let result = RestoreSeries200ResponseResultsInner(
            bookId: UUID(),
            title: "Book One",
            status: .initiated
        )
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/series/\(seriesId.uuidString)/restore")
            XCTAssertEqual(request.httpMethod, "POST")
            return self.makeJSONResponse(statusCode: 200, object: RestoreSeries200Response(
                message: "Restore initiated for 1 book",
                total: 1,
                results: [result]
            ))
        }

        // When
        let response = try await sut.restoreSeries(seriesId: seriesId)

        // Then
        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.status, .initiated)
        XCTAssertEqual(response.results.first?.title, "Book One")
    }
}
