//
//  AuthManager.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation
import Security

/// Manages user authentication and token storage
@MainActor
class AuthManager: ObservableObject, AuthManaging {
    static let shared = AuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoringSession = true  // Track session restoration state
    @Published var errorMessage: String?

    private var apiClient: APIClientProtocol
    private let keychain: KeychainStoring
    private var refreshTokenValue: UUID?

    // Keychain keys
    private let accessTokenKey = "com.bookvault.accessToken"
    private let refreshTokenKey = "com.bookvault.refreshToken"
    private let userDataKey = "com.bookvault.userData"

    // Callback for clearing caches on logout (enables DI for testing)
    var clearCachesOnLogout: () -> Void = {
        LibraryCacheManager.shared.clearCache()
        OfflineProgressStore.shared.clearCache()
        ProgressManager.shared.clearCache()
        AudioPlayerManager.shared.stop()  // Stop audio playback on logout
    }

    // Public access to token for authenticated requests (e.g., audio streaming)
    var token: String? {
        keychain.load(key: accessTokenKey)
    }

    // Public access to user email
    var userEmail: String? {
        currentUser?.email
    }

    // Production singleton init
    private convenience init() {
        self.init(
            apiClient: APIClient.shared,
            keychain: SystemKeychain.shared
        )
        // Try to restore session from keychain
        Task {
            await restoreSession()
        }
    }

    // Testable initializer (no automatic session restoration)
    init(apiClient: APIClientProtocol, keychain: KeychainStoring) {
        self.apiClient = apiClient
        self.keychain = keychain
        self.isRestoringSession = false  // Tests manage their own session state
    }

    // MARK: - Public Methods

    /// Login with email and password
    func login(email: String, password: String) async {
        DebugLogger.auth("Login attempt for email: \(email)")
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.login(email: email, password: password)
            DebugLogger.auth("Login API response received - expiresIn: \(response.expiresIn)s")

            // Store tokens securely
            try keychain.save(key: accessTokenKey, value: response.accessToken)
            try keychain.save(key: refreshTokenKey, value: response.refreshToken.uuidString)
            DebugLogger.auth("Tokens saved to keychain - refreshToken: \(String(response.refreshToken.uuidString.prefix(8)))...")

            // Store user data
            let userData = try JSONEncoder().encode(response.user)
            try keychain.save(key: userDataKey, value: String(data: userData, encoding: .utf8)!)

            // Update APIClient's token for subsequent requests
            apiClient.accessToken = response.accessToken

            // Update state
            self.currentUser = response.user
            self.refreshTokenValue = response.refreshToken
            self.isAuthenticated = true

            DebugLogger.auth("Login successful - user: \(response.user.email), tokenExpiresIn: \(response.expiresIn)s")
            isLoading = false
        } catch {
            DebugLogger.error("Login failed for \(email)", error: error)
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    /// Logout and clear all stored credentials
    func logout() async {
        DebugLogger.auth("Logout initiated by user")
        isLoading = true
        errorMessage = nil

        // Try to logout on server
        if let refreshToken = refreshTokenValue {
            do {
                DebugLogger.auth("Sending logout request to server")
                try await apiClient.logout(refreshToken: refreshToken)
                DebugLogger.auth("Server logout successful")
            } catch {
                // Continue with local logout even if server request fails
                DebugLogger.warning("Server logout failed, continuing with local logout: \(error.localizedDescription)")
            }
        } else {
            DebugLogger.auth("No refresh token available for server logout")
        }

        // Clear all stored data
        clearSession()

        isLoading = false
    }

    /// Force logout due to invalid/expired token (called when API returns 401)
    /// This clears the session immediately without trying to call the server
    func forceLogout() {
        DebugLogger.auth("Force logout triggered - token invalid or expired")
        clearSession()
        errorMessage = "Your session has expired. Please log in again."
    }

    /// Refresh the access token using the refresh token
    func refreshAccessToken() async -> Bool {
        guard let refreshToken = refreshTokenValue else {
            DebugLogger.error("REFRESH FAILED: No refresh token in memory (refreshTokenValue is nil)")
            return false
        }

        DebugLogger.auth("Refresh attempt starting - refreshToken: \(String(refreshToken.uuidString.prefix(8)))...")

        do {
            DebugLogger.auth("Sending refresh request to /api/auth/mobile/refresh")
            let response = try await apiClient.refreshToken(refreshToken: refreshToken)
            DebugLogger.auth("Refresh API response received - new expiresIn: \(response.expiresIn)s")

            // Update stored access token in keychain
            try keychain.save(key: accessTokenKey, value: response.accessToken)
            DebugLogger.auth("New access token saved to keychain")

            // Store the rotated refresh token (token rotation for security)
            try keychain.save(key: refreshTokenKey, value: response.refreshToken.uuidString)
            self.refreshTokenValue = response.refreshToken
            DebugLogger.auth("Rotated refresh token saved - new token: \(String(response.refreshToken.uuidString.prefix(8)))...")

            // Update APIClient's token so subsequent requests use the new token
            apiClient.accessToken = response.accessToken

            DebugLogger.success("Token refresh successful - session extended for \(response.expiresIn)s")
            return true
        } catch let error as APIError {
            // Log specific API error details
            switch error {
            case .unauthorized:
                DebugLogger.error("REFRESH FAILED: Server returned 401 Unauthorized - refresh token may be invalid/expired")
            case .serverError(let code, let message):
                DebugLogger.error("REFRESH FAILED: Server error \(code) - \(message ?? "no message")")
            case .networkError(let underlying):
                DebugLogger.error("REFRESH FAILED: Network error - \(underlying.localizedDescription)")
            case .decodingError(let underlying):
                DebugLogger.error("REFRESH FAILED: Decoding error - \(underlying.localizedDescription)")
            default:
                DebugLogger.error("REFRESH FAILED: API error - \(error.localizedDescription)")
            }
            DebugLogger.auth("Clearing session due to refresh failure")
            clearSession()
            return false
        } catch {
            DebugLogger.error("REFRESH FAILED: Unexpected error - \(error.localizedDescription)")
            DebugLogger.auth("Clearing session due to refresh failure")
            clearSession()
            return false
        }
    }

    // MARK: - Private Methods

    /// Restore session from keychain
    private func restoreSession() async {
        DebugLogger.auth("Session restoration starting...")

        defer {
            isRestoringSession = false
            DebugLogger.auth("Session restoration complete - isAuthenticated: \(isAuthenticated), hasRefreshToken: \(refreshTokenValue != nil)")
        }

        // Check what's in keychain
        let hasAccessToken = keychain.load(key: accessTokenKey) != nil
        let hasRefreshToken = keychain.load(key: refreshTokenKey) != nil
        let hasUserData = keychain.load(key: userDataKey) != nil
        DebugLogger.auth("Keychain state - accessToken: \(hasAccessToken), refreshToken: \(hasRefreshToken), userData: \(hasUserData)")

        guard let accessToken = keychain.load(key: accessTokenKey),
              let refreshTokenString = keychain.load(key: refreshTokenKey),
              let refreshToken = UUID(uuidString: refreshTokenString),
              let userDataString = keychain.load(key: userDataKey),
              let userData = userDataString.data(using: .utf8)
        else {
            DebugLogger.auth("Session restoration: Missing or invalid session data in keychain")
            return
        }

        DebugLogger.auth("Found refresh token in keychain: \(String(refreshTokenString.prefix(8)))...")

        do {
            let user = try JSONDecoder().decode(User.self, from: userData)

            // IMPORTANT: Set refreshTokenValue BEFORE accessToken to prevent race condition
            // where API call triggers 401 before refresh token is available
            self.refreshTokenValue = refreshToken

            // Restore to API client
            apiClient.accessToken = accessToken

            // Update state
            self.currentUser = user
            self.isAuthenticated = true

            DebugLogger.auth("Session restored for user: \(user.email) - access token may be expired, refresh will happen on first 401")
        } catch {
            // If we can't decode user data, clear everything
            DebugLogger.error("Session restoration failed - could not decode user data", error: error)
            clearSession()
        }
    }

    /// Clear all session data
    /// Note: Biometric enrollment is intentionally NOT cleared on logout.
    /// Users stay enrolled for faster re-login. If password is changed on web,
    /// biometric login will fail and user will need to re-enable after password login.
    private func clearSession() {
        DebugLogger.auth("Clearing session - removing all auth data")

        // Clear keychain
        keychain.delete(key: accessTokenKey)
        keychain.delete(key: refreshTokenKey)
        keychain.delete(key: userDataKey)
        DebugLogger.auth("Keychain tokens deleted")

        // Clear API client token
        apiClient.accessToken = nil

        // Clear offline caches and stop audio (Phase 8: security - prevent cross-user data access)
        clearCachesOnLogout()
        DebugLogger.auth("Offline caches cleared, audio stopped")

        // Clear state
        self.currentUser = nil
        self.refreshTokenValue = nil
        self.isAuthenticated = false

        DebugLogger.auth("Session cleared - isAuthenticated: false")
    }
}
