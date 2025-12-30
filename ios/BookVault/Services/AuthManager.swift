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
    @Published var errorMessage: String?

    private let apiClient: APIClientProtocol
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

    // Testable initializer
    init(apiClient: APIClientProtocol, keychain: KeychainStoring) {
        self.apiClient = apiClient
        self.keychain = keychain
    }

    // MARK: - Public Methods

    /// Login with email and password
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.login(email: email, password: password)

            // Store tokens securely
            try keychain.save(key: accessTokenKey, value: response.accessToken)
            try keychain.save(key: refreshTokenKey, value: response.refreshToken.uuidString)

            // Store user data
            let userData = try JSONEncoder().encode(response.user)
            try keychain.save(key: userDataKey, value: String(data: userData, encoding: .utf8)!)

            // Update state
            self.currentUser = response.user
            self.refreshTokenValue = response.refreshToken
            self.isAuthenticated = true

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    /// Logout and clear all stored credentials
    func logout() async {
        isLoading = true
        errorMessage = nil

        // Try to logout on server
        if let refreshToken = refreshTokenValue {
            do {
                try await apiClient.logout(refreshToken: refreshToken)
            } catch {
                // Continue with local logout even if server request fails
                print("Logout request failed: \(error)")
            }
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
            return false
        }

        do {
            let response = try await apiClient.refreshToken(refreshToken: refreshToken)

            // Update stored access token
            try keychain.save(key: accessTokenKey, value: response.accessToken)

            return true
        } catch {
            // If refresh fails, clear session
            clearSession()
            return false
        }
    }

    // MARK: - Private Methods

    /// Restore session from keychain
    private func restoreSession() async {
        guard let accessToken = keychain.load(key: accessTokenKey),
              let refreshTokenString = keychain.load(key: refreshTokenKey),
              let refreshToken = UUID(uuidString: refreshTokenString),
              let userDataString = keychain.load(key: userDataKey),
              let userData = userDataString.data(using: .utf8) else {
            return
        }

        do {
            let user = try JSONDecoder().decode(User.self, from: userData)

            // Restore to API client
            var mutableApiClient = apiClient
            mutableApiClient.accessToken = accessToken

            // Update state
            self.currentUser = user
            self.refreshTokenValue = refreshToken
            self.isAuthenticated = true
        } catch {
            // If we can't decode user data, clear everything
            clearSession()
        }
    }

    /// Clear all session data
    private func clearSession() {
        // Clear keychain
        keychain.delete(key: accessTokenKey)
        keychain.delete(key: refreshTokenKey)
        keychain.delete(key: userDataKey)

        // Clear API client token (only if mutable - production APIClient has var accessToken)
        var mutableApiClient = apiClient
        mutableApiClient.accessToken = nil

        // Clear offline caches (Phase 8: security - prevent cross-user data access)
        clearCachesOnLogout()
        DebugLogger.auth("Offline caches cleared on logout")

        // Clear state
        self.currentUser = nil
        self.refreshTokenValue = nil
        self.isAuthenticated = false
    }
}
