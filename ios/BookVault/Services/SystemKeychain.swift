//
//  SystemKeychain.swift
//  BookVault
//
//  Created for Phase 4 testing support.
//  Production implementation of KeychainStoring using Security framework.
//

import Foundation
import Security

// MARK: - SystemKeychain

/// Production implementation of KeychainStoring using the system Security framework
///
/// Sendable: stateless (no stored properties) — every call goes straight to the
/// Security framework, which is itself thread-safe.
final class SystemKeychain: KeychainStoring, Sendable {
    static let shared = SystemKeychain()

    /// Accessibility class for every item this store writes.
    ///
    /// This app plays audio in the background, so the streaming path reads the
    /// access token while the screen is locked. The keychain default,
    /// `kSecAttrAccessibleWhenUnlocked`, makes items unreadable the moment the
    /// device locks: the resource loader then got `nil` for the token, failed
    /// the byte-range request, and stopped playback — and on the next
    /// foreground, session restoration read `nil` too and showed
    /// "Your session has expired."
    ///
    /// `AfterFirstUnlock` keeps items readable while locked, from the first
    /// unlock after a reboot onward. `ThisDeviceOnly` keeps them out of iCloud
    /// keychain and encrypted backups, so widening lock-state access does not
    /// also widen where the tokens can travel.
    ///
    /// Note this is deliberately *weaker on lock state* than the biometric
    /// password in `BiometricAuthManager`, which stays
    /// `WhenUnlockedThisDeviceOnly` behind a biometry ACL — that item is only
    /// ever read during an interactive login, so it has no reason to survive a
    /// lock.
    /// Held as `String` rather than `CFString` so it satisfies Swift 6's
    /// `Sendable` requirement for static storage; it is bridged back when the
    /// query dictionary is built.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private init() {}

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Identifies the item; must not carry value/attribute keys so it can be
        // reused as the delete query.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        // Delete any existing item. A pre-fix item carries the old
        // `WhenUnlocked` accessibility, and `SecItemAdd` would not change it —
        // replacing the item outright is what migrates it.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = Self.accessibility

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    func read(key: String) -> KeychainReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                return .notFound
            }
            return .found(value)

        case errSecInteractionNotAllowed:
            // The item exists but the device is locked and its accessibility
            // class forbids reading. Transient — never treat as logged out.
            DebugLogger.auth("Keychain read blocked for \(key) - device locked (errSecInteractionNotAllowed)")
            return .locked

        default:
            return .notFound
        }
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - KeychainError

/// Errors that can occur during keychain operations
enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode value for keychain storage"
        case let .saveFailed(status):
            "Failed to save to keychain (status: \(status))"
        }
    }
}
