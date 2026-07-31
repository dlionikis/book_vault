//
//  CarPlayCoordinatorTests.swift
//  BookVaultTests
//
//  CarPlay task C1/C3 — auth-state template switching.
//

import Combine
import XCTest
@testable import BookVault

// MARK: - MockAuthManagerForCarPlay

/// Minimal `AuthManaging` double.
///
/// Only the three auth-state properties matter here; everything else satisfies
/// the protocol and is unused. `@unchecked Sendable` for the usual test-double
/// reason: one instance per test, driven from one place.
@MainActor
final class MockAuthManagerForCarPlay: ObservableObject, AuthManaging, @unchecked Sendable {
    @Published var isAuthenticated = false
    @Published var isRestoringSession = false

    var isOfflineMode = false
    var hasRestorableSession = false
    var currentUser: User?
    var isLoading = false
    var errorMessage: String?
    var token: String?
    var username: String?

    func login(username _: String, password _: String) async {}
    func logout() async {}
    func forceLogout() {}
    func refreshAccessToken() async -> Bool { false }
    func enterOfflineMode() {}
    func promoteToOnlineIfPossible() async {}
}

// MARK: - Tests

@MainActor
final class CarPlayCoordinatorTests: XCTestCase {
    private var mockAuth: MockAuthManagerForCarPlay!
    private var mockLibrary: MockLibraryManager!
    private var authSubject: PassthroughSubject<Void, Never>!
    private var sut: CarPlayCoordinator!

    override func setUp() async throws {
        mockAuth = MockAuthManagerForCarPlay()
        mockLibrary = MockLibraryManager()
        authSubject = PassthroughSubject<Void, Never>()

        sut = CarPlayCoordinator(
            provider: CarPlayLibraryProvider(
                libraryManager: mockLibrary,
                apiClient: MockAPIClient(),
                storageManager: MockStorageManager(),
                networkMonitor: MockNetworkMonitor()
            ),
            imageProvider: CarPlayImageProvider(coverCache: MockCoverCacheManager()),
            authManager: mockAuth,
            onAuthChange: authSubject.eraseToAnyPublisher(),
            onPlay: { _ in }
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockAuth = nil
        mockLibrary = nil
        authSubject = nil
    }

    /// The cold-start case the plan calls out (finding #4): `isRestoringSession`
    /// starts true, and CarPlay can connect before the keychain read finishes.
    /// Treating that as "logged out" would flash a false sign-in screen every
    /// launch.
    func testRestoringSessionIsNotTreatedAsLoggedOut() async {
        mockAuth.isRestoringSession = true
        mockAuth.isAuthenticated = false

        let template = await sut.rootTemplateForCurrentState()

        XCTAssertEqual(template, .loading,
                       "Session restore must show a neutral state, not the sign-in message")
    }

    func testLoggedOutShowsSignIn() async {
        mockAuth.isRestoringSession = false
        mockAuth.isAuthenticated = false

        let template = await sut.rootTemplateForCurrentState()

        XCTAssertEqual(template, .signIn)
    }

    func testAuthenticatedShowsBrowseTabs() async {
        mockAuth.isRestoringSession = false
        mockAuth.isAuthenticated = true

        let template = await sut.rootTemplateForCurrentState()

        XCTAssertEqual(template, .browse)
    }

    /// Restore resolving into a signed-in session must move off the loading
    /// state — the transition, not just the endpoints.
    func testRestoreResolvingToSignedInSwitchesToBrowse() async {
        mockAuth.isRestoringSession = true
        var template = await sut.rootTemplateForCurrentState()
        XCTAssertEqual(template, .loading)

        mockAuth.isRestoringSession = false
        mockAuth.isAuthenticated = true

        template = await sut.rootTemplateForCurrentState()
        XCTAssertEqual(template, .browse)
    }

    /// A logout on the phone while CarPlay is connected must swap the root
    /// template rather than leaving stale, unplayable rows on screen.
    func testLogoutMidSessionSwitchesToSignIn() async {
        mockAuth.isRestoringSession = false
        mockAuth.isAuthenticated = true
        let beforeLogout = await sut.rootTemplateForCurrentState()
        XCTAssertEqual(beforeLogout, .browse)

        mockAuth.isAuthenticated = false

        let afterLogout = await sut.rootTemplateForCurrentState()
        XCTAssertEqual(afterLogout, .signIn)
    }
}
