//
//  KeychainStoring.swift
//  BookVault
//
//  Created for Phase 4 testing support.
//  Enables testing AuthManager with mock keychain.
//

import Foundation

// MARK: - KeychainReadResult

/// The outcome of a keychain read.
///
/// The three cases exist because "no value" and "cannot read the value right
/// now" have opposite consequences for the session. A missing token means the
/// user is logged out; a token that is merely unreadable because the device is
/// locked is transient, and treating it as missing logs the user out mid-
/// playback. Collapsing both into `nil` was the cause of the
/// "session has expired" prompt after a locked-screen listening session.
enum KeychainReadResult: Equatable {
    /// The value was read successfully.
    case found(String)

    /// No item exists for this key.
    case notFound

    /// An item may exist but is unreadable right now — the device is locked and
    /// the item's accessibility class requires an unlocked device
    /// (`errSecInteractionNotAllowed`). Retry once the device is unlocked.
    case locked

    /// The value, if one was readable. `nil` for both `.notFound` and `.locked`.
    var value: String? {
        if case let .found(value) = self { return value }
        return nil
    }

    /// Whether the read failed only because the device is locked.
    var isLocked: Bool {
        self == .locked
    }
}

// MARK: - KeychainStoring

/// Protocol for keychain storage to enable testing with mocks
protocol KeychainStoring {
    /// Save a value to the keychain
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    /// - Throws: Error if save fails
    func save(key: String, value: String) throws

    /// Load a value from the keychain, distinguishing "absent" from
    /// "temporarily unreadable because the device is locked".
    ///
    /// Prefer this over `load(key:)` anywhere a missing value would tear down
    /// the session.
    /// - Parameter key: The key to load
    /// - Returns: The read outcome
    func read(key: String) -> KeychainReadResult

    /// Load a value from the keychain
    /// - Parameter key: The key to load
    /// - Returns: The stored string value, or nil if not found
    func load(key: String) -> String?

    /// Delete a value from the keychain
    /// - Parameter key: The key to delete
    func delete(key: String)
}

extension KeychainStoring {
    /// Default `load` in terms of `read`, so conformers only implement the
    /// richer operation and the two can never disagree.
    func load(key: String) -> String? {
        read(key: key).value
    }
}
