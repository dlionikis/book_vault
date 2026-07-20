//
//  NotificationRegistrarTests.swift
//  BookVaultTests
//
//  Phase 7b: authorization + device-token registration (device-free, via mocks).
//

import UserNotifications
import XCTest
@testable import BookVault

// MARK: - Test doubles

private struct StubAuthorizer: NotificationAuthorizing {
    let granted: Bool
    var error: Error?
    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        if let error { throw error }
        return granted
    }
}

@MainActor
private final class SpyRemoteRegistrar: RemoteNotificationRegistering {
    private(set) var registerCallCount = 0
    func registerForRemoteNotifications() { registerCallCount += 1 }
}

@MainActor
final class NotificationRegistrarTests: XCTestCase {
    private var mockAPIClient: MockAPIClient!
    private var spyApp: SpyRemoteRegistrar!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        spyApp = SpyRemoteRegistrar()
    }

    override func tearDown() async throws {
        mockAPIClient = nil
        spyApp = nil
    }

    private func makeSUT(granted: Bool = true, authError: Error? = nil) -> NotificationRegistrar {
        NotificationRegistrar(
            apiClient: mockAPIClient,
            authorizer: StubAuthorizer(granted: granted, error: authError),
            application: spyApp
        )
    }

    // MARK: - Authorization

    func testGrantedAuthorizationTriggersAPNsRegistration() async {
        let sut = makeSUT(granted: true)
        await sut.requestAuthorizationAndRegister()
        XCTAssertEqual(spyApp.registerCallCount, 1)
    }

    func testDeniedAuthorizationDoesNotRegister() async {
        let sut = makeSUT(granted: false)
        await sut.requestAuthorizationAndRegister()
        XCTAssertEqual(spyApp.registerCallCount, 0)
    }

    func testAuthorizationErrorIsSwallowed() async {
        let sut = makeSUT(granted: true, authError: NSError(domain: "test", code: 1))
        await sut.requestAuthorizationAndRegister() // must not throw
        XCTAssertEqual(spyApp.registerCallCount, 0)
    }

    // MARK: - Token upload

    func testRegisterTokenConvertsDataToHexAndUploads() async {
        let sut = makeSUT()
        // 0x00 0x0f 0xff → "000fff"
        let data = Data([0x00, 0x0F, 0xFF])

        await sut.registerToken(data)

        XCTAssertEqual(mockAPIClient.registerDeviceTokenCalls, ["000fff"])
    }

    func testRegisterTokenDeduplicatesSameToken() async {
        let sut = makeSUT()
        await sut.registerTokenString("deadbeef")
        await sut.registerTokenString("deadbeef") // duplicate — should be skipped

        XCTAssertEqual(mockAPIClient.registerDeviceTokenCalls, ["deadbeef"])
    }

    func testRegisterTokenUploadsAgainWhenTokenChanges() async {
        let sut = makeSUT()
        await sut.registerTokenString("aaaa")
        await sut.registerTokenString("bbbb")

        XCTAssertEqual(mockAPIClient.registerDeviceTokenCalls, ["aaaa", "bbbb"])
    }

    func testRegisterTokenFailureIsSwallowed() async {
        mockAPIClient.registerDeviceTokenResult = .failure(APIError.serverError(500, nil))
        let sut = makeSUT()

        await sut.registerTokenString("cccc") // must not throw

        XCTAssertEqual(mockAPIClient.registerDeviceTokenCalls, ["cccc"])
    }
}
