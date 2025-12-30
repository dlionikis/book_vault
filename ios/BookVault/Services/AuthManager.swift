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

    private let apiClient = APIClient.shared
    private var refreshTokenValue: UUID?

    // Keychain keys
    private let accessTokenKey = "com.bookvault.accessToken"
    private let refreshTokenKey = "com.bookvault.refreshToken"
    private let userDataKey = "com.bookvault.userData"

    // Public access to token for authenticated requests (e.g., audio streaming)
    var token: String? {
        loadFromKeychain(key: accessTokenKey)
    }

    // Public access to user email
    var userEmail: String? {
        currentUser?.email
    }

    private init() {
        // Try to restore session from keychain
        Task {
            await restoreSession()
        }
    }

    // MARK: - Public Methods

    /// Login with email and password
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.login(email: email, password: password)

            // Store tokens securely
            try saveToKeychain(key: accessTokenKey, value: response.accessToken)
            try saveToKeychain(key: refreshTokenKey, value: response.refreshToken.uuidString)

            // Store user data
            let userData = try JSONEncoder().encode(response.user)
            try saveToKeychain(key: userDataKey, value: String(data: userData, encoding: .utf8)!)

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
            try saveToKeychain(key: accessTokenKey, value: response.accessToken)

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
        guard let accessToken = loadFromKeychain(key: accessTokenKey),
              let refreshTokenString = loadFromKeychain(key: refreshTokenKey),
              let refreshToken = UUID(uuidString: refreshTokenString),
              let userDataString = loadFromKeychain(key: userDataKey),
              let userData = userDataString.data(using: .utf8) else {
            return
        }

        do {
            let user = try JSONDecoder().decode(User.self, from: userData)

            // Restore to API client
            apiClient.accessToken = accessToken

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
        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        deleteFromKeychain(key: userDataKey)

        // Clear API client token
        apiClient.accessToken = nil

        // Clear offline caches (Phase 8: security - prevent cross-user data access)
        LibraryCacheManager.shared.clearCache()
        OfflineProgressStore.shared.clearCache()
        DebugLogger.auth("Offline caches cleared on logout")

        // Clear state
        self.currentUser = nil
        self.refreshTokenValue = nil
        self.isAuthenticated = false
    }

    // MARK: - Keychain Helpers

    /// Save a value to the keychain
    private func saveToKeychain(key: String, value: String) throws {
        let data = value.data(using: .utf8)!

        // Create query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainError", code: Int(status), userInfo: nil)
        }
    }

    /// Load a value from the keychain
    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Delete a value from the keychain
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
