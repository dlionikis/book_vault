//
//  AuthManaging.swift
//  BookVault
//
//  Created for testing support.
//

import Foundation

/// Protocol for AuthManager to enable testing with mocks
@MainActor
protocol AuthManaging: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get set }
    var token: String? { get }
    var userEmail: String? { get }

    func login(email: String, password: String) async
    func logout() async
    func forceLogout()
    func refreshAccessToken() async -> Bool
}
