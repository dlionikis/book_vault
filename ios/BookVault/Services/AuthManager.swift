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
    @Published private(set) var isOfflineMode = false      // Local offline-only session (Phase 8b)
    @Published var errorMessage: String?

    private var apiClient: APIClientProtocol
    private let keychain: KeychainStoring
    private let networkMonitor: any NetworkMonitoring
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

    // Public access to username
    var username: String? {
        currentUser?.username
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
    init(apiClient: APIClientProtocol,
         keychain: KeychainStoring,
         networkMonitor: any NetworkMonitoring = NetworkMonitor.shared) {
        self.apiClient = apiClient
        self.keychain = keychain
        self.networkMonitor = networkMonitor
        self.isRestoringSession = false  // Tests manage their own session state
    }

    // MARK: - Public Methods

    /// Login with username and password
    func login(username: String, password: String) async {
        DebugLogger.auth("Login attempt for username: \(username)")
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.login(username: username, password: password)
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

            DebugLogger.auth("Login successful - user: \(response.user.username), tokenExpiresIn: \(response.expiresIn)s")
            isLoading = false
        } catch {
            DebugLogger.error("Login failed for \(username)", error: error)
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

        // Do not attempt (or let a failure tear down the session) when offline.
        // A network-caused refresh failure is transient, not an auth rejection,
        // so clearing the session here would strand a merely-offline user at the
        // login screen. Keep the session and let the app fall into offline mode.
        guard networkMonitor.isConnected else {
            DebugLogger.auth("Refresh skipped - device offline; preserving session")
            return false
        }

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
            // Only a genuine auth rejection (401) should tear the session down.
            // Network/decoding/5xx failures are transient — preserve the session
            // so the user keeps a working offline experience.
            switch error {
            case .unauthorized:
                DebugLogger.error("REFRESH FAILED: Server returned 401 Unauthorized - refresh token invalid/expired")
                DebugLogger.auth("Clearing session due to auth rejection")
                clearSession()
                return false
            case let .serverError(code, message):
                DebugLogger.error("REFRESH FAILED: Server error \(code) - \(message ?? "no message")")
                if code == 401 {
                    DebugLogger.auth("Clearing session due to 401 server error")
                    clearSession()
                }
                return false // 5xx and other server errors are transient - keep session
            case let .networkError(underlying):
                DebugLogger.error("REFRESH FAILED: Network error - \(underlying.localizedDescription); preserving session")
                return false
            case let .decodingError(underlying):
                DebugLogger.error("REFRESH FAILED: Decoding error - \(underlying.localizedDescription); preserving session")
                return false
            default:
                DebugLogger.error("REFRESH FAILED: API error - \(error.localizedDescription); preserving session")
                return false
            }
        } catch {
            DebugLogger.error("REFRESH FAILED: Unexpected error - \(error.localizedDescription); preserving session")
            return false
        }
    }

    // MARK: - Offline Mode (Phase 8b)

    /// True when a prior online session's user data still lives in the keychain,
    /// meaning an offline session can be reconstructed on this device.
    var hasRestorableSession: Bool {
        keychain.load(key: userDataKey) != nil
    }

    /// Enter a local, offline-only session. Rehydrates the cached user so that
    /// user-scoped caches (library, progress) resolve, without claiming an
    /// online-verified session. Downloaded audio plays entirely from local disk.
    ///
    /// Callers are expected to gate this behind identity verification (biometric)
    /// so it is not an authentication bypass.
    func enterOfflineMode() {
        guard let userDataString = keychain.load(key: userDataKey),
              let userData = userDataString.data(using: .utf8),
              let user = try? JSONDecoder().decode(User.self, from: userData)
        else {
            DebugLogger.auth("enterOfflineMode: no cached user to restore")
            errorMessage = "No offline session available on this device."
            return
        }

        // Restore any cached tokens. The access token may be expired; that is
        // fine because offline mode only touches local content.
        if let accessToken = keychain.load(key: accessTokenKey) {
            apiClient.accessToken = accessToken
        }
        if let refreshTokenString = keychain.load(key: refreshTokenKey) {
            refreshTokenValue = UUID(uuidString: refreshTokenString)
        }

        currentUser = user
        isOfflineMode = true
        isRestoringSession = false
        errorMessage = nil
        DebugLogger.auth("Entered offline mode for user: \(user.username)")
    }

    /// Called when connectivity returns during an offline session. Attempts a
    /// token refresh and, on success, upgrades to a full online session so the
    /// online-only tabs become available again.
    func promoteToOnlineIfPossible() async {
        guard isOfflineMode else { return }
        DebugLogger.auth("Connectivity returned in offline mode - attempting to promote to online")
        if await refreshAccessToken() {
            isAuthenticated = true
            isOfflineMode = false
            DebugLogger.success("Offline session promoted to online")
        } else {
            DebugLogger.auth("Promotion failed - remaining in offline mode")
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

            DebugLogger.auth("Session restored for user: \(user.username) - access token may be expired, refresh will happen on first 401")
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
        self.isOfflineMode = false

        DebugLogger.auth("Session cleared - isAuthenticated: false")
    }
}
