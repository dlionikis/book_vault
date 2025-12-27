//
//  APIClient.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import Foundation

/// API client for Book Vault backend
/// Uses generated models from OpenAPI specification
class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        // Use localhost for development
        // TODO: Switch to production URL after deployment
        self.baseURL = URL(string: "http://localhost:3000")!
        self.session = URLSession.shared
    }

    // MARK: - Authentication
    // TODO: Implement auth methods using generated models

    // MARK: - Books
    // TODO: Implement book fetching using generated models

    // MARK: - Progress
    // TODO: Implement progress sync using generated models
}
