# iOS API Integration Guide

**Status**: ✅ Implementation Complete (Reference Document)
**Last Updated**: December 29, 2025

> **TL;DR**: All API endpoints documented with Swift implementation examples. Uses JWT authentication and generated models from OpenAPI spec.
>
> **Note**: This document contains patterns and examples from the completed iOS implementation. Use as reference for debugging or understanding API integration patterns.

---

## Authentication Flow

### Login

**Endpoint**: `POST /api/auth/login`

**Request**:

```swift
struct LoginRequest: Codable {
    let email: String
    let password: String
}
```

**Response**:

```swift
struct LoginResponse: Codable {
    let token: String
    let user: User
}

struct User: Codable {
    let id: String
    let email: String
}
```

**Implementation**:

```swift
func login(email: String, password: String) async throws -> LoginResponse {
    let url = URL(string: "\(baseURL)/api/auth/login")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = LoginRequest(email: email, password: password)
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw NetworkError.unauthorized
    }

    return try JSONDecoder().decode(LoginResponse.self, from: data)
}
```

### Token Storage (Keychain)

```swift
class KeychainHelper {
    private let tokenKey = "com.bookvault.jwt"

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey
        ]

        SecItemDelete(query as CFDictionary)
    }
}
```

### Authenticated Requests

**Add JWT to Authorization header**:

```swift
private func authenticatedRequest<T: Decodable>(
    url: URL,
    method: String = "GET",
    body: Encodable? = nil
) async throws -> T {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    // Add JWT token
    if let token = keychainHelper.loadToken() {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // Add body if provided
    if let body = body {
        request.httpBody = try JSONEncoder().encode(body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        if httpResponse.statusCode == 401 {
            throw NetworkError.unauthorized
        }
        throw NetworkError.httpError(httpResponse.statusCode)
    }

    return try JSONDecoder().decode(T.self, from: data)
}
```

---

## Book Endpoints

### Get Books (Paginated)

**Endpoint**: `GET /api/books?page={page}&limit={limit}`

**Response**:

```swift
struct BookListResponse: Codable {
    let books: [Book]
    let pagination: Pagination
}

struct Pagination: Codable {
    let page: Int
    let limit: Int
    let total: Int
    let totalPages: Int
}
```

**Implementation**:

```swift
func getBooks(page: Int = 1, limit: Int = 20) async throws -> BookListResponse {
    let url = URL(string: "\(baseURL)/api/books?page=\(page)&limit=\(limit)")!
    return try await authenticatedRequest(url: url)
}
```

### Get Book by ID

**Endpoint**: `GET /api/books/{id}`

**Response**:

```swift
struct Book: Codable, Identifiable {
    let id: String
    let asin: String
    let title: String
    let description: String?
    let runtimeMinutes: Int
    let releaseDate: String?
    let publisher: String?
    let coverUrl: String
    let audioUrl: String
    let authors: [Author]
    let narrators: [Narrator]
    let series: [SeriesInfo]
    let categories: [Category]
}

struct Author: Codable, Identifiable {
    let id: String
    let name: String
    let asin: String?
}

struct Narrator: Codable, Identifiable {
    let id: String
    let name: String
    let asin: String?
}

struct SeriesInfo: Codable, Identifiable {
    let id: String
    let title: String
    let sequence: String?
    let asin: String?
}

struct Category: Codable, Identifiable {
    let id: String
    let name: String
}
```

**Implementation**:

```swift
func getBook(id: String) async throws -> Book {
    let url = URL(string: "\(baseURL)/api/books/\(id)")!
    return try await authenticatedRequest(url: url)
}
```

---

## Chapter Endpoints

### Get Chapters

**Endpoint**: `GET /api/books/{id}/chapters`

**Response**:

```swift
struct ChapterListResponse: Codable {
    let chapters: [Chapter]
}

struct Chapter: Codable, Identifiable {
    let id: String
    let title: String
    let startTime: Double
    let endTime: Double
    let index: Int

    var duration: Double {
        endTime - startTime
    }
}
```

**Implementation**:

```swift
func getChapters(bookId: String) async throws -> [Chapter] {
    let url = URL(string: "\(baseURL)/api/books/\(bookId)/chapters")!
    let response: ChapterListResponse = try await authenticatedRequest(url: url)
    return response.chapters
}
```

---

## Progress Endpoints

### Get User Progress

**Endpoint**: `GET /api/progress?bookId={bookId}`

**Response**:

```swift
struct UserProgress: Codable {
    let id: String
    let bookId: String
    let userId: String
    let positionSeconds: Double
    let completed: Bool
    let lastPlayed: String
}
```

**Implementation**:

```swift
func getProgress(bookId: String) async throws -> UserProgress? {
    let url = URL(string: "\(baseURL)/api/progress?bookId=\(bookId)")!
    return try? await authenticatedRequest(url: url)
}
```

### Update Progress

**Endpoint**: `POST /api/progress`

**Request**:

```swift
struct UpdateProgressRequest: Codable {
    let bookId: String
    let positionSeconds: Double
    let completed: Bool
}
```

**Response**:

```swift
struct UpdateProgressResponse: Codable {
    let success: Bool
    let progress: UserProgress
}
```

**Implementation**:

```swift
func updateProgress(bookId: String, position: Double, completed: Bool = false) async throws {
    let url = URL(string: "\(baseURL)/api/progress")!
    let request = UpdateProgressRequest(
        bookId: bookId,
        positionSeconds: position,
        completed: completed
    )

    let _: UpdateProgressResponse = try await authenticatedRequest(
        url: url,
        method: "POST",
        body: request
    )
}
```

**Auto-save during playback**:

```swift
// In AudioPlayerService
private var progressTimer: Timer?

func startProgressSync() {
    // Save progress every 10 seconds
    progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
        guard let self = self,
              let bookId = self.currentBook?.id else { return }

        Task {
            try? await self.apiClient.updateProgress(
                bookId: bookId,
                position: self.currentTime
            )
        }
    }
}
```

---

## Search Endpoints

### Search

**Endpoint**: `GET /api/search?q={query}&type={type}`

**Parameters**:

- `q`: Search query string
- `type`: Optional filter (`books`, `authors`, `narrators`, `series`)

**Response**:

```swift
struct SearchResponse: Codable {
    let books: [Book]
    let authors: [Author]
    let narrators: [Narrator]
    let series: [SeriesInfo]
}
```

**Implementation**:

```swift
func search(query: String, type: String? = nil) async throws -> SearchResponse {
    var components = URLComponents(string: "\(baseURL)/api/search")!
    components.queryItems = [
        URLQueryItem(name: "q", value: query)
    ]
    if let type = type {
        components.queryItems?.append(URLQueryItem(name: "type", value: type))
    }

    return try await authenticatedRequest(url: components.url!)
}
```

---

## Browse Endpoints

### Browse by Authors

**Endpoint**: `GET /api/browse/authors?page={page}&limit={limit}`

**Response**:

```swift
struct AuthorListResponse: Codable {
    let authors: [AuthorWithCount]
    let pagination: Pagination
}

struct AuthorWithCount: Codable {
    let author: Author
    let bookCount: Int
}
```

**Implementation**:

```swift
func getAuthors(page: Int = 1, limit: Int = 50) async throws -> AuthorListResponse {
    let url = URL(string: "\(baseURL)/api/browse/authors?page=\(page)&limit=\(limit)")!
    return try await authenticatedRequest(url: url)
}
```

### Browse by Series

**Endpoint**: `GET /api/browse/series?page={page}&limit={limit}`

**Response**:

```swift
struct SeriesListResponse: Codable {
    let series: [SeriesWithCount]
    let pagination: Pagination
}

struct SeriesWithCount: Codable {
    let series: SeriesInfo
    let bookCount: Int
}
```

### Get Books by Author

**Endpoint**: `GET /api/browse/authors/{id}/books`

**Response**:

```swift
struct AuthorBooksResponse: Codable {
    let author: Author
    let books: [Book]
}
```

---

## Library Endpoints

### Get User Library

**Endpoint**: `GET /api/library`

**Response**:

```swift
struct LibraryResponse: Codable {
    let books: [Book]
}
```

**Implementation**:

```swift
func getLibrary() async throws -> [Book] {
    let url = URL(string: "\(baseURL)/api/library")!
    let response: LibraryResponse = try await authenticatedRequest(url: url)
    return response.books
}
```

### Add Book to Library

**Endpoint**: `POST /api/library/add`

**Request**:

```swift
struct AddToLibraryRequest: Codable {
    let bookId: String
}
```

**Implementation**:

```swift
func addToLibrary(bookId: String) async throws {
    let url = URL(string: "\(baseURL)/api/library/add")!
    let request = AddToLibraryRequest(bookId: bookId)

    let _: SuccessResponse = try await authenticatedRequest(
        url: url,
        method: "POST",
        body: request
    )
}
```

### Remove Book from Library

**Endpoint**: `POST /api/library/remove`

**Request**:

```swift
struct RemoveFromLibraryRequest: Codable {
    let bookId: String
}
```

---

## User Lists Endpoints

### Get User Lists

**Endpoint**: `GET /api/lists`

**Response**:

```swift
struct UserListsResponse: Codable {
    let lists: [UserList]
}

struct UserList: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let bookCount: Int
    let createdAt: String
}
```

### Get List Books

**Endpoint**: `GET /api/lists/{id}/books`

**Response**:

```swift
struct ListBooksResponse: Codable {
    let list: UserList
    let books: [Book]
}
```

### Create List

**Endpoint**: `POST /api/lists`

**Request**:

```swift
struct CreateListRequest: Codable {
    let name: String
    let description: String?
}
```

---

## Error Handling

### Network Errors

```swift
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(Int)
    case decodingError(Error)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized. Please log in again."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkUnavailable:
            return "No internet connection"
        }
    }
}
```

### Retry Logic

```swift
func requestWithRetry<T: Decodable>(
    url: URL,
    maxRetries: Int = 3
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<maxRetries {
        do {
            return try await authenticatedRequest(url: url)
        } catch {
            lastError = error

            // Don't retry on 4xx errors
            if let networkError = error as? NetworkError,
               case .httpError(let code) = networkError,
               (400...499).contains(code) {
                throw error
            }

            // Exponential backoff
            if attempt < maxRetries - 1 {
                let delay = pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    throw lastError ?? NetworkError.invalidResponse
}
```

---

## Environment Configuration

```swift
enum Environment {
    case development
    case production
}

struct Config {
    static let environment: Environment = .development

    static var baseURL: String {
        switch environment {
        case .development:
            #if targetEnvironment(simulator)
            return "http://localhost:3000"
            #else
            // Replace with your Mac's local IP
            return "http://192.168.1.100:3000"
            #endif
        case .production:
            return "https://api.bookvault.com"
        }
    }
}
```

---

## Testing API Integration

### Mock URLSession

```swift
class MockURLSession: URLSessionProtocol {
    var nextData: Data?
    var nextResponse: URLResponse?
    var nextError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = nextError {
            throw error
        }

        let data = nextData ?? Data()
        let response = nextResponse ?? HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
```

### Test Example

```swift
class APIClientTests: XCTestCase {
    var apiClient: APIClient!
    var mockSession: MockURLSession!

    override func setUp() {
        mockSession = MockURLSession()
        apiClient = APIClient(session: mockSession)
    }

    func testGetBooks() async throws {
        // Load fixture from test-fixtures/
        let fixture = loadFixture("books-list.json")
        mockSession.nextData = fixture

        let response = try await apiClient.getBooks()

        XCTAssertEqual(response.books.count, 10)
        XCTAssertEqual(response.pagination.total, 100)
    }

    func testGetBooksUnauthorized() async {
        mockSession.nextResponse = HTTPURLResponse(
            url: URL(string: "http://test.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )

        do {
            _ = try await apiClient.getBooks()
            XCTFail("Should throw unauthorized error")
        } catch NetworkError.unauthorized {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
```

---

## Best Practices

1. **Use Generated Models**: Generate from OpenAPI spec for type safety
2. **Centralize API Client**: Use singleton or dependency injection
3. **Handle Errors Gracefully**: Show user-friendly error messages
4. **Cache Responses**: Use URLCache for images and data
5. **Retry Failed Requests**: Implement exponential backoff for transient errors
6. **Validate Tokens**: Check token expiry before making requests
7. **Test with Mocks**: Use mock URLSession for unit tests
8. **Monitor Network**: Check for connectivity before making requests
