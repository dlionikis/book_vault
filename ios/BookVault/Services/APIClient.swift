//
//  APIClient.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

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

// MARK: - Restore / archive types

/// Result of requesting a download URL for a book.
///
/// The download endpoint returns two different bodies by status code:
/// `200` (ready) → `GenerateDownloadUrl200Response`, `202` (archived) →
/// `BookStreamResponse` with `status == .restoring`. This enum lets callers
/// branch without inspecting HTTP status codes themselves.
enum DownloadUrlResult {
    /// The audio is available; a presigned URL was issued.
    case ready(GenerateDownloadUrl200Response)
    /// The audio is archived in cold storage; a restore was initiated (or is
    /// already in flight). Retry the download once the restore completes.
    case restoring(BookStreamResponse)
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

    /// Single-flight refresh coordination. Shared with the AVPlayer streaming
    /// path (see `AudioPlayerManager`) so both 401 paths join one refresh
    /// instead of racing and double-consuming the rotated refresh token.
    let refreshCoordinator: TokenRefreshCoordinator

    /// Collapses the N concurrent "force logout" calls a single refresh failure
    /// would otherwise produce into one. Re-armed on successful login.
    private let logoutGate = OneShotGate()

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
        // Share the app-wide coordinator with the AVPlayer streaming path.
        self.init(baseURL: URL(string: urlString)!, session: session, refreshCoordinator: .shared)
    }

    // Testable initializer - accepts custom URLSession for URLProtocol interception.
    // `refreshCoordinator` defaults to a fresh instance; production passes the
    // app-wide one so the streaming path shares it.
    init(baseURL: URL, session: URLSession, refreshCoordinator: TokenRefreshCoordinator = TokenRefreshCoordinator()) {
        self.baseURL = baseURL
        self.session = session
        self.refreshCoordinator = refreshCoordinator

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
                    await forceLogoutOnce()
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
                await forceLogoutOnce()
            }
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            let errorMessage = try? decoder.decode([String: String].self, from: data)
            throw APIError.serverError(httpResponse.statusCode, errorMessage?["error"])
        }
    }

    /// Execute a request and return the HTTP status code plus the raw body,
    /// applying the same 401 → token-refresh → retry handling as `execute<T>`
    /// but leaving status interpretation and decoding to the caller.
    ///
    /// Used by endpoints whose success responses vary by status code (e.g. the
    /// download endpoint: `200` ready vs `202` restoring — different bodies).
    /// 401 (after a failed refresh) and 404 still throw the usual `APIError`;
    /// everything else in `200...299` is returned verbatim.
    private func executeRaw(request: URLRequest) async throws -> (statusCode: Int, data: Data) {
        let path = request.url?.path ?? "unknown"
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        DebugLogger.apiResponse(
            path: request.url?.absoluteString ?? "unknown",
            statusCode: httpResponse.statusCode,
            body: Self.truncatedResponseBody(from: data)
        )

        switch httpResponse.statusCode {
        case 200 ... 299:
            return (httpResponse.statusCode, data)
        case 401:
            DebugLogger.auth("Received 401 for \(path) - attempting token refresh...")
            if await attemptTokenRefresh() {
                var retryRequest = request
                if let newToken = accessToken {
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                }
                let (data2, response2) = try await session.data(for: retryRequest)
                guard let httpResponse2 = response2 as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                switch httpResponse2.statusCode {
                case 200 ... 299:
                    return (httpResponse2.statusCode, data2)
                case 401:
                    if accessToken != nil { await forceLogoutOnce() }
                    throw APIError.unauthorized
                case 404:
                    throw APIError.notFound
                default:
                    let msg = try? decoder.decode([String: String].self, from: data2)
                    throw APIError.serverError(httpResponse2.statusCode, msg?["error"])
                }
            } else {
                if accessToken != nil { await forceLogoutOnce() }
                throw APIError.unauthorized
            }
        case 404:
            throw APIError.notFound
        default:
            let errorMessage = try? decoder.decode([String: String].self, from: data)
            DebugLogger.error("API request failed: \(path) - status \(httpResponse.statusCode)")
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
    /// Returns true if refresh succeeded. If one is already in progress —
    /// started here or by the streaming path — waits for it and returns its result.
    private func attemptTokenRefresh() async -> Bool {
        // Claim-or-join is a single atomic step inside the actor, so concurrent
        // 401s produce exactly one refresh. The coordinator is shared with the
        // AVPlayer streaming path, so a streaming refresh and an API refresh
        // can never run at once and double-consume the rotated refresh token.
        let handler = tokenRefreshHandler
        return await refreshCoordinator.refresh(using: handler)
    }

    /// Force a logout exactly once per session teardown.
    ///
    /// Every in-flight request that 401s independently reaches a logout path,
    /// so without this guard a single refresh failure fires N logouts for N
    /// concurrent requests. Collapsing them keeps one failure from tearing the
    /// session down N times over.
    private func forceLogoutOnce() async {
        guard await logoutGate.claim() else {
            DebugLogger.auth("Force logout already performed for this session - skipping duplicate")
            return
        }
        forceLogoutHandler()
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

        // Re-arm the logout gate: this is a new session, and it must be able to
        // force a logout of its own if its credentials later go bad.
        await logoutGate.reset()

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
        struct LogoutBody: Encodable { let refreshToken: UUID }
        let requestBody = LogoutBody(refreshToken: refreshToken)
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

    /// Fetch the combined Series-mode feed for Catalog (series + standalone books, interleaved alphabetically).
    func fetchCatalogSeriesView(page: Int = 1, limit: Int = 20) async throws -> GetCatalogSeriesView200Response {
        var components = URLComponents(string: "/api/browse/catalog-series-view")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let request = try createRequest(
            path: components.url!.absoluteString,
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Fetch the combined Series-mode feed for Library (owned series + standalone owned books).
    func fetchLibrarySeriesView(page: Int = 1, limit: Int = 20) async throws -> GetLibrarySeriesView200Response {
        var components = URLComponents(string: "/api/browse/library-series-view")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

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
    ) async throws -> GetProgress200Response {
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
    func addToLibrary(bookId: UUID) async throws -> LogoutMobile200Response {
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

        let _: LogoutMobile200Response = try await execute(request: request)
    }

    // MARK: - Downloads (Authenticated)

    /// Check whether the current user is eligible to download a book
    func checkDownloadEligibility(bookId: UUID) async throws -> CheckDownloadEligibility200Response {
        let request = try createRequest(
            path: "/api/downloads/\(bookId.uuidString)/check",
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Generate a pre-signed download URL for a book.
    ///
    /// Returns `.ready` (200) with a presigned URL, or `.restoring` (202) when
    /// the audio is archived in cold storage and a restore was initiated. The
    /// caller decides how to surface the restoring case.
    func generateDownloadUrl(bookId: UUID, deviceId: String?) async throws -> DownloadUrlResult {
        let requestBody = GenerateDownloadUrlRequest(deviceId: deviceId)
        let request = try createRequest(
            path: "/api/downloads/\(bookId.uuidString)",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )

        let (statusCode, data) = try await executeRaw(request: request)
        if statusCode == 202 {
            let restoring: BookStreamResponse = try decodeResponse(data: data)
            return .restoring(restoring)
        }
        let ready: GenerateDownloadUrl200Response = try decodeResponse(data: data)
        return .ready(ready)
    }

    // MARK: - Streaming (Authenticated)

    /// Fetch an on-demand streaming URL for a book.
    ///
    /// Phase 0 of the archive/restore workflow: replaces streaming directly from
    /// `book.audioUrl` (which is being phased out of list responses). A future
    /// release returns `status == .restoring` when the audio is archived.
    func getBookStream(bookId: UUID) async throws -> BookStreamResponse {
        let request = try createRequest(
            path: "/api/books/\(bookId.uuidString)/stream",
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    // MARK: - Restore / Archive (Authenticated)

    /// Explicitly request a restore for an archived audiobook (the "Request
    /// restore" button) without pretending to play.
    ///
    /// Idempotent: an in-flight restore is reused. Returns `status == .available`
    /// (200) when the file turns out not to be archived, or `.restoring` (202)
    /// when a restore is initiated/ongoing. Both share `BookStreamResponse`, so
    /// the caller reads `.status` rather than the HTTP code.
    func restoreBook(bookId: UUID) async throws -> BookStreamResponse {
        let request = try createRequest(
            path: "/api/books/\(bookId.uuidString)/restore",
            method: "POST",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Fetch the cached restore/availability state for a book. Used to poll
    /// while a restore is in progress.
    func getBookRestoreStatus(bookId: UUID) async throws -> RestoreStatus {
        let request = try createRequest(
            path: "/api/books/\(bookId.uuidString)/restore-status",
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// List the caller's in-progress restores plus those completed in the last
    /// 7 days, newest first.
    func listRestores() async throws -> RestoresListResponse {
        let request = try createRequest(
            path: "/api/books/restores",
            method: "GET",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    /// Batch-restore every archived audiobook in a series (the "Restore All
    /// Archived" button). Idempotent per book; already-available books are
    /// skipped. Returns a per-book result list. Phase 8.
    func restoreSeries(seriesId: UUID) async throws -> RestoreSeries200Response {
        let request = try createRequest(
            path: "/api/series/\(seriesId.uuidString)/restore",
            method: "POST",
            requiresAuth: true
        )

        return try await execute(request: request)
    }

    // MARK: - Notifications (Authenticated)

    /// Register (or refresh) this device's APNs token so the backend can send
    /// push notifications. Idempotent per (user, token). Phase 7b.
    @discardableResult
    func registerDeviceToken(deviceToken: String) async throws -> RegisterDeviceToken200Response {
        let requestBody = RegisterDeviceTokenRequest(deviceToken: deviceToken, platform: .ios)
        let request = try createRequest(
            path: "/api/notifications/register",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )

        return try await execute(request: request)
    }
}
