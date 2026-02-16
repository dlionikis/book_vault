//
//  APIClient.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

// MARK: - TokenRefreshCoordinator

/// Actor to coordinate token refresh across concurrent requests (Swift 6 async-safe)
/// Ensures only one refresh happens at a time; other callers wait for the result
private actor TokenRefreshCoordinator {
    private var isRefreshing = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    /// Attempt to start a refresh. Returns nil if we should proceed with refresh,
    /// or a continuation to await if refresh is already in progress.
    func beginRefresh() -> CheckedContinuation<Bool, Never>? {
        if isRefreshing {
            // Already refreshing - caller should wait
            return nil // Signal that caller needs to create a continuation
        }
        isRefreshing = true
        return nil
    }

    /// Check if refresh is in progress
    func isRefreshInProgress() -> Bool {
        isRefreshing
    }

    /// Add a waiter continuation to be resumed when refresh completes
    func addWaiter(_ continuation: CheckedContinuation<Bool, Never>) {
        waiters.append(continuation)
    }

    /// Complete the refresh and resume all waiting continuations
    func completeRefresh(success: Bool) -> [CheckedContinuation<Bool, Never>] {
        let currentWaiters = waiters
        waiters.removeAll()
        isRefreshing = false
        return currentWaiters
    }

    /// Mark refresh as started (called after checking isRefreshInProgress)
    func markRefreshStarted() {
        isRefreshing = true
    }
}

// MARK: - APIError

/// Errors that can occur during API operations
enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case serverError(Int, String?)
    case unauthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            "Invalid response from server"
        case let .decodingError(error):
            "Failed to decode response: \(error.localizedDescription)"
        case let .serverError(code, message):
            "Server error (\(code)): \(message ?? "Unknown error")"
        case .unauthorized:
            "Unauthorized - please log in again"
        case .notFound:
            "Resource not found"
        }
    }
}

// MARK: - APIClient

/// API client for Book Vault backend
/// Uses generated models from OpenAPI specification
class APIClient: APIClientProtocol {
    static let shared = APIClient()

    let baseURL: URL // Changed from private to allow SearchManager access
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Note: Debug logging now handled by DebugLogger class
    // No need for custom flag anymore

    // Token storage (will be managed by AuthManager)
    var accessToken: String?

    // Force logout callback (enables DI for testing)
    var forceLogoutHandler: () -> Void = {
        Task { @MainActor in
            AuthManager.shared.forceLogout()
        }
    }

    // Token refresh callback (enables DI for testing)
    var tokenRefreshHandler: () async -> Bool = {
        await AuthManager.shared.refreshAccessToken()
    }

    // Token refresh coordinator (actor-based for Swift 6 async safety)
    private let refreshCoordinator = TokenRefreshCoordinator()

    // Production singleton init - reads API URL from Info.plist (set via xcconfig)
    private convenience init() {
        // Read API base URL from Info.plist (injected from xcconfig based on build configuration)
        let urlString: String
        if let configuredURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           !configuredURL.isEmpty {
            urlString = configuredURL
        } else {
            // Fallback to localhost for development if not configured
            urlString = "http://localhost:3000"
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)
        self.init(baseURL: URL(string: urlString)!, session: session)
    }

    // Testable initializer - accepts custom URLSession for URLProtocol interception
    init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session

        DebugLogger.network("APIClient initialized with base URL: \(baseURL.absoluteString)")

        // Configure JSON decoder with custom date handling
        self.decoder = JSONDecoder()
        // Use custom date decoding to handle both full ISO8601 and date-only formats
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 format first (e.g., "2022-08-08T00:00:00Z" or "2025-12-28T19:07:21.367Z")
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds (fallback for older formats)
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try date-only format (e.g., "2022-08-08")
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }

        // Configure JSON encoder
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Private Helpers

    /// Truncates large API response bodies for debug logging
    /// Only called via @autoclosure, so this is skipped entirely in release builds
    private static func truncatedResponseBody(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        // Check for common array fields (books, library, items, etc.)
        let arrayKeys = ["books", "library", "items", "results", "data"]
        var truncated = json
        var truncationNote: String?

        for key in arrayKeys {
            if let array = json[key] as? [[String: Any]], array.count > 1 {
                // Keep only first item
                truncated[key] = [array[0]]
                truncationNote = "[\(key): showing 1 of \(array.count) items, rest truncated]"
                break
            }
        }

        if let note = truncationNote,
           let truncatedData = try? JSONSerialization.data(withJSONObject: truncated),
           let truncatedString = String(data: truncatedData, encoding: .utf8) {
            return "\(note)\n\(truncatedString)"
        }

        return String(data: data, encoding: .utf8)
    }

    /// Creates a URL request with common headers
    private func createRequest(
        path: String,
        method: String,
        body: Encodable? = nil,
        requiresAuth: Bool = false
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization header if required
        if requiresAuth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode body if present
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    /// Executes a request and decodes the response
    /// On 401, attempts token refresh before forcing logout
    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
        let path = request.url?.path ?? "unknown"
        let hasAuth = request.value(forHTTPHeaderField: "Authorization") != nil
        DebugLogger.auth("API request: \(request.httpMethod ?? "?") \(path) - hasAuthHeader: \(hasAuth)")

        // Check if task is already cancelled before making request
        if Task.isCancelled {
            DebugLogger.error("🚫 Task already cancelled BEFORE request: \(path)")
        }

        DebugLogger.info("🌐 URLSession.data starting for: \(path)")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
            DebugLogger.info("🌐 URLSession.data completed for: \(path)")
        } catch {
            let nsError = error as NSError
            DebugLogger.error("🌐 URLSession.data FAILED for: \(path) - code: \(nsError.code), domain: \(nsError.domain)")
            if Task.isCancelled {
                DebugLogger.error("🚫 Task is cancelled AFTER request failed: \(path)")
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogger.error("API request failed: Invalid response type")
            throw APIError.invalidResponse
        }

        // Debug logging - uses @autoclosure so truncation only runs in debug builds
        DebugLogger.apiResponse(
            path: request.url?.absoluteString ?? "unknown",
            statusCode: httpResponse.statusCode,
            body: Self.truncatedResponseBody(from: data)
        )

        // Handle HTTP error codes
        switch httpResponse.statusCode {
        case 200 ... 299:
            // Success - decode response
            return try decodeResponse(data: data)
        case 401:
            // Attempt token refresh before forcing logout
            DebugLogger.auth("Received 401 Unauthorized for \(path) - access token expired, attempting refresh...")
            if await attemptTokenRefresh() {
                // Retry the original request with new token
                DebugLogger.auth("Token refresh succeeded - retrying original request to \(path)")
                var retryRequest = request
                if let newToken = accessToken {
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                }
                return try await executeWithoutRefresh(request: retryRequest)
            } else {
                // Refresh failed - force logout (only if not already logged out)
                DebugLogger.error("Token refresh failed - cannot recover, forcing logout")
                if accessToken != nil {
                    forceLogoutHandler()
                }
                throw APIError.unauthorized
            }
        case 404:
            throw APIError.notFound
        default:
            // Try to decode error message
            let errorMessage = try? decoder.decode([String: String].self, from: data)
            DebugLogger.error("API request failed: \(path) - status \(httpResponse.statusCode)")
            throw APIError.serverError(httpResponse.statusCode, errorMessage?["error"])
        }
    }

    /// Execute request without attempting refresh (used for retry after refresh)
    private func executeWithoutRefresh<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Debug logging
        let responseBody = String(data: data, encoding: .utf8)
        DebugLogger.apiResponse(
            path: request.url?.absoluteString ?? "unknown",
            statusCode: httpResponse.statusCode,
            body: responseBody
        )

        switch httpResponse.statusCode {
        case 200 ... 299:
            return try decodeResponse(data: data)
        case 401:
            // Second 401 after refresh - definitely log out (only if not already logged out)
            DebugLogger.auth("Second 401 after token refresh - forcing logout")
            if accessToken != nil {
                forceLogoutHandler()
            }
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            let errorMessage = try? decoder.decode([String: String].self, from: data)
            throw APIError.serverError(httpResponse.statusCode, errorMessage?["error"])
        }
    }

    /// Decode response data with detailed error logging
    private func decodeResponse<T: Decodable>(data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Detailed error logging (automatically disabled in release builds)
            DebugLogger.error("Failed to decode API response", error: error)

            if let decodingError = error as? DecodingError {
                switch decodingError {
                case let .keyNotFound(key, context):
                    DebugLogger.error("Missing key: \(key.stringValue) | Context: \(context.debugDescription)")
                case let .typeMismatch(type, context):
                    DebugLogger.error("Type mismatch: expected \(type) | Context: \(context.debugDescription)")
                case let .valueNotFound(type, context):
                    DebugLogger.error("Value not found: \(type) | Context: \(context.debugDescription)")
                case let .dataCorrupted(context):
                    DebugLogger.error("Data corrupted: \(context.debugDescription)")
                @unknown default:
                    DebugLogger.error("Unknown decoding error")
                }
            }
     
            throw APIError.decodingError(error)
        }
    }

    /// Attempt to refresh the access token
    /// Returns true if refresh succeeded, false otherwise
    /// If refresh is already in progress, waits for it to complete and returns the same result
    private func attemptTokenRefresh() async -> Bool {
        // Check if refresh is already in progress (actor-isolated, async-safe)
        if await refreshCoordinator.isRefreshInProgress() {
            DebugLogger.auth("Token refresh already in progress - waiting for result...")

            // Create a continuation and register as a waiter
            return await withCheckedContinuation { continuation in
                Task {
                    await refreshCoordinator.addWaiter(continuation)
                }
            }
        }

        // We're the first - mark refresh as started
        await refreshCoordinator.markRefreshStarted()

        // Perform the actual refresh
        let success = await tokenRefreshHandler()

        // Complete refresh and get all waiting continuations
        let waiters = await refreshCoordinator.completeRefresh(success: success)

        DebugLogger.auth("Token refresh completed (success: \(success)) - resuming \(waiters.count) waiting requests")

        for waiter in waiters {
            waiter.resume(returning: success)
        }

        return success
    }

    // MARK: - Authentication

    /// Login with username and password
    func login(username: String, password: String) async throws -> LoginMobile200Response {
        let requestBody = LoginMobileRequest(username: username, password: password)
        let request = try createRequest(
            path: "/api/auth/mobile/login",
            method: "POST",
            body: requestBody,
            requiresAuth: false
        )

        let response: LoginMobile200Response = try await execute(request: request)

        // Store the access token
        self.accessToken = response.accessToken

        return response
    }

    /// Refresh access token
    /// NOTE: Uses executeWithoutRefresh to avoid deadlock if refresh endpoint returns 401
    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response {
        DebugLogger.auth("APIClient.refreshToken called with token: \(String(refreshToken.uuidString.prefix(8)))...")

        let requestBody = RefreshTokenRequest(refreshToken: refreshToken)
        let request = try createRequest(
            path: "/api/auth/mobile/refresh",
            method: "POST",
            body: requestBody,
            requiresAuth: false
        )

        DebugLogger.auth("Sending refresh request to server...")

        // IMPORTANT: Use executeWithoutRefresh to avoid deadlock
        // If we used execute() and the refresh endpoint returned 401,
        // it would try to refresh again, causing infinite recursion/deadlock
        let response: RefreshToken200Response = try await executeWithoutRefresh(request: request)

        DebugLogger.auth("Refresh response received - new token expiresIn: \(response.expiresIn)s")

        // Update the access token
        self.accessToken = response.accessToken

        return response
    }

    /// Logout
    func logout(refreshToken: UUID) async throws {
        let requestBody = LogoutMobileRequest(refreshToken: refreshToken)
        let request = try createRequest(
            path: "/api/auth/mobile/logout",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )

        let _: LogoutMobile200Response = try await execute(request: request)

        // Clear the access token
        self.accessToken = nil
    }

    // MARK: - Books

    /// Fetch list of books with pagination
    func fetchBooks(page: Int = 1, limit: Int = 20, sortBy: String? = nil) async throws -> ListBooks200Response {
        var components = URLComponents(string: "/api/books")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let sortBy {
            queryItems.append(URLQueryItem(name: "sortBy", value: sortBy))
        }

        components.queryItems = queryItems

        let request = try createRequest(
            path: components.url!.absoluteString,
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Fetch a specific book by ID
    func fetchBook(id: UUID) async throws -> Book {
        let request = try createRequest(
            path: "/api/books/\(id.uuidString)",
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Fetch chapters for a book
    func fetchBookChapters(bookId: UUID) async throws -> [Chapter] {
        let request = try createRequest(
            path: "/api/books/\(bookId.uuidString)/chapters",
            method: "GET",
            requiresAuth: true
        )

        let response: GetBookChapters200Response = try await execute(request: request)
        return response.chapters
    }

    // MARK: - Progress (Authenticated)

    /// Get user's progress for a book
    func fetchProgress(bookId: UUID) async throws -> GetProgress200Response {
        var components = URLComponents(string: "/api/progress")!
        components.queryItems = [URLQueryItem(name: "bookId", value: bookId.uuidString)]

        let request = try createRequest(
            path: components.url!.absoluteString,
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Update user's progress for a book
    func updateProgress(bookId: UUID, positionSeconds: Double) async throws -> UpdateProgress200Response {
        let requestBody = UpdateProgressRequest(bookId: bookId, positionSeconds: positionSeconds)
        let request = try createRequest(
            path: "/api/progress",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Set book completion status
    func setProgressStatus(
        bookId: UUID,
        status: SetProgressStatusRequest.Status
    ) async throws -> SetProgressStatus200Response {
        let requestBody = SetProgressStatusRequest(bookId: bookId, status: status)
        let request = try createRequest(
            path: "/api/progress",
            method: "PUT",
            body: requestBody,
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    // MARK: - Library (Authenticated)

    /// Get user's library
    func fetchLibrary() async throws -> GetLibrary200Response {
        let request = try createRequest(
            path: "/api/library",
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Add book to user's library
    func addToLibrary(bookId: UUID) async throws -> AddToLibrary201Response {
        let requestBody = AddToLibraryRequest(bookId: bookId)
        let request = try createRequest(
            path: "/api/library",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Remove book from user's library
    func removeFromLibrary(bookId: UUID) async throws {
        let request = try createRequest(
            path: "/api/library/\(bookId.uuidString)",
            method: "DELETE",
            requiresAuth: true
        )

        let _: RemoveFromLibrary200Response = try await execute(request: request)
    }
}
