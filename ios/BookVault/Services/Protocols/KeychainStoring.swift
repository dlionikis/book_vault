//
//  KeychainStoring.swift
//  BookVault
//
//  Created for Phase 4 testing support.
//  Enables testing AuthManager with mock keychain.
//

import Foundation

/// Protocol for keychain storage to enable testing with mocks
protocol KeychainStoring {
    /// Save a value to the keychain
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    /// - Throws: Error if save fails
    func save(key: String, value: String) throws

    /// Load a value from the keychain
    /// - Parameter key: The key to load
    /// - Returns: The stored string value, or nil if not found
    func load(key: String) -> String?

    /// Delete a value from the keychain
    /// - Parameter key: The key to delete
    func delete(key: String)
}
