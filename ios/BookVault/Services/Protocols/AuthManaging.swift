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
    var isRestoringSession: Bool { get }
    var isOfflineMode: Bool { get }
    var hasRestorableSession: Bool { get }
    var currentUser: User? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get set }
    var token: String? { get }
    var username: String? { get }

    func login(username: String, password: String) async
    func logout() async
    func forceLogout()
    func refreshAccessToken() async -> Bool
    func enterOfflineMode()
    func promoteToOnlineIfPossible() async
}
