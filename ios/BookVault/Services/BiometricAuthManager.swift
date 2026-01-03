//
//  BiometricAuthManager.swift
//  BookVault
//
//  Manages Face ID / Touch ID authentication for faster login.
//  Uses biometric-protected keychain storage for credentials.
//

import Foundation
import LocalAuthentication

// MARK: - BiometricAuthManager

/// Manages Face ID / Touch ID authentication
@MainActor
final class BiometricAuthManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var biometryType: LABiometryType = .none
    @Published private(set) var canUseBiometrics: Bool = false
    @Published private(set) var isBiometricEnabled: Bool = false

    // MARK: - Constants

    private enum Keys {
        static let biometricEnabled = "biometricEnabled"
        static let biometricEmail = "biometricEmail"
        static let biometricPassword = "com.bookvault.biometricPassword"
    }

    // MARK: - Singleton

    static let shared = BiometricAuthManager()

    private init() {
        checkBiometricAvailability()
        loadBiometricPreference()
    }

    // MARK: - Public Methods

    /// Check if device supports biometric authentication
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        biometryType = context.biometryType
    }

    /// Returns user-friendly name for biometric type
    var biometryName: String {
        switch biometryType {
        case .none: return "Biometrics"
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometrics"
        }
    }

    /// Authenticate user with biometrics and retrieve stored password
    func authenticateAndGetCredentials() async throws -> (email: String, password: String) {
        guard isBiometricEnabled else {
            throw BiometricError.notEnabled
        }

        guard canUseBiometrics else {
            throw BiometricError.notAvailable
        }

        // Authenticate with biometrics
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Log in to Book Vault"
        )

        guard success else {
            throw BiometricError.authenticationFailed
        }

        // Retrieve stored credentials
        guard let email = UserDefaults.standard.string(forKey: Keys.biometricEmail),
              let password = try retrievePassword() else {
            throw BiometricError.credentialsNotFound
        }

        return (email, password)
    }

    /// Enable biometric login for a user
    func enableBiometric(email: String, password: String) throws {
        // Store password with biometric protection
        try storePassword(password)

        // Store email and enable flag
        UserDefaults.standard.set(email, forKey: Keys.biometricEmail)
        UserDefaults.standard.set(true, forKey: Keys.biometricEnabled)

        isBiometricEnabled = true
    }

    /// Disable biometric login
    func disableBiometric() {
        // Remove stored password
        deletePassword()

        // Clear preferences
        UserDefaults.standard.removeObject(forKey: Keys.biometricEmail)
        UserDefaults.standard.removeObject(forKey: Keys.biometricEnabled)

        isBiometricEnabled = false
    }

    /// Check if biometric is enabled for a specific email
    func isBiometricEnabledFor(email: String) -> Bool {
        guard isBiometricEnabled else { return false }
        let storedEmail = UserDefaults.standard.string(forKey: Keys.biometricEmail)
        return storedEmail?.lowercased() == email.lowercased()
    }

    // MARK: - Private Methods

    private func loadBiometricPreference() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: Keys.biometricEnabled)
    }

    /// Store password with biometric protection
    private func storePassword(_ password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw BiometricError.encodingFailed
        }

        // Create access control with biometric requirement
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw BiometricError.accessControlCreationFailed
        }

        // Delete existing item first
        deletePassword()

        // Add new item with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Keys.biometricPassword,
            kSecValueData as String: passwordData,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricError.keychainSaveFailed(status)
        }
    }

    /// Retrieve password (requires biometric auth already completed)
    private func retrievePassword() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Keys.biometricPassword,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    /// Delete stored password
    private func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Keys.biometricPassword
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - BiometricError

/// Errors that can occur during biometric authentication
enum BiometricError: LocalizedError {
    case notAvailable
    case notEnabled
    case authenticationFailed
    case credentialsNotFound
    case encodingFailed
    case accessControlCreationFailed
    case keychainSaveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notEnabled:
            return "Biometric login is not enabled"
        case .authenticationFailed:
            return "Biometric authentication failed"
        case .credentialsNotFound:
            return "Stored credentials not found. Please log in with your password."
        case .encodingFailed:
            return "Failed to encode credentials"
        case .accessControlCreationFailed:
            return "Failed to create secure storage"
        case .keychainSaveFailed(let status):
            return "Failed to save credentials (error \(status))"
        }
    }
}
