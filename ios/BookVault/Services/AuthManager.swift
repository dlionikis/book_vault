//
//  AuthManager.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

/// Placeholder User model (will be replaced by generated model)
struct User: Codable {
    let id: String
    let email: String
}

/// Manages authentication state and token storage
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private let keychainService = "com.bookvault.auth"

    // MARK: - Token Management
    // TODO: Implement keychain storage for JWT tokens

    // MARK: - Authentication
    // TODO: Implement login/logout using APIClient
}
