//
//  APIClient.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

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
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .unauthorized:
            return "Unauthorized - please log in again"
        case .notFound:
            return "Resource not found"
        }
    }
}

/// API client for Book Vault backend
/// Uses generated models from OpenAPI specification
class APIClient {
    static let shared = APIClient()

    let baseURL: URL  // Changed from private to allow SearchManager access
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Note: Debug logging now handled by DebugLogger class
    // No need for custom flag anymore

    // Token storage (will be managed by AuthManager)
    var accessToken: String?

    private init() {
        // Determine the appropriate base URL
        // FORCE localhost for all builds during development
        let urlString = "http://localhost:3000"

        self.baseURL = URL(string: urlString)!

        DebugLogger.network("APIClient initialized with base URL: \(urlString)")

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

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
        }

        // Configure JSON encoder
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        // Initialize URLSession with standard configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Private Helpers

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
        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    /// Executes a request and decodes the response
    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Debug logging (automatically disabled in release builds)
        let responseBody = String(data: data, encoding: .utf8)
        DebugLogger.apiResponse(
            path: request.url?.absoluteString ?? "unknown",
            statusCode: httpResponse.statusCode,
            body: responseBody
        )

        // Handle HTTP error codes
        switch httpResponse.statusCode {
        case 200...299:
            // Success - decode response
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                // Detailed error logging (automatically disabled in release builds)
                DebugLogger.error("Failed to decode API response", error: error)

                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        DebugLogger.error("Missing key: \(key.stringValue) | Context: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        DebugLogger.error("Type mismatch: expected \(type) | Context: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        DebugLogger.error("Value not found: \(type) | Context: \(context.debugDescription)")
                    case .dataCorrupted(let context):
                        DebugLogger.error("Data corrupted: \(context.debugDescription)")
                    @unknown default:
                        DebugLogger.error("Unknown decoding error")
                    }
                }
                throw APIError.decodingError(error)
            }
        case 401:
            // Force logout on main actor to redirect to login screen
            Task { @MainActor in
                AuthManager.shared.forceLogout()
            }
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            // Try to decode error message
            let errorMessage = try? decoder.decode([String: String].self, from: data)
            throw APIError.serverError(httpResponse.statusCode, errorMessage?["error"])
        }
    }

    // MARK: - Authentication

    /// Login with email and password
    func login(email: String, password: String) async throws -> LoginMobile200Response {
        let requestBody = LoginMobileRequest(email: email, password: password)
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
    func refreshToken(refreshToken: UUID) async throws -> RefreshToken200Response {
        let requestBody = RefreshTokenRequest(refreshToken: refreshToken)
        let request = try createRequest(
            path: "/api/auth/mobile/refresh",
            method: "POST",
            body: requestBody,
            requiresAuth: false
        )

        let response: RefreshToken200Response = try await execute(request: request)

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

        if let sortBy = sortBy {
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
    func setProgressStatus(bookId: UUID, status: SetProgressStatusRequest.Status) async throws -> SetProgressStatus200Response {
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
