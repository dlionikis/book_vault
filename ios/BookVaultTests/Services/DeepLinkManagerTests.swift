//
//  DeepLinkManagerTests.swift
//  BookVaultTests
//
//  Phase 7b: APNs payload → DeepLink parsing (device-free).
//

import XCTest
@testable import BookVault

@MainActor
final class DeepLinkManagerTests: XCTestCase {
    // MARK: - Payload parsing

    func testParsesRestoreCompletePayload() {
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Audiobook Ready", "body": "…"], "sound": "default"],
            "bookId": bookId,
            "action": "restore_complete"
        ]

        let link = DeepLinkManager.deepLink(from: userInfo)

        XCTAssertEqual(link, .book(id: bookId))
    }

    func testMissingBookIdYieldsNil() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "Something"],
            "action": "restore_complete"
        ]
        XCTAssertNil(DeepLinkManager.deepLink(from: userInfo))
    }

    func testEmptyBookIdYieldsNil() {
        let userInfo: [AnyHashable: Any] = ["bookId": "", "action": "restore_complete"]
        XCTAssertNil(DeepLinkManager.deepLink(from: userInfo))
    }

    func testNonStringBookIdYieldsNil() {
        let userInfo: [AnyHashable: Any] = ["bookId": 12345, "action": "restore_complete"]
        XCTAssertNil(DeepLinkManager.deepLink(from: userInfo))
    }

    // MARK: - Published state

    func testHandleNotificationPublishesPendingLink() {
        let sut = DeepLinkManager()
        XCTAssertNil(sut.pendingDeepLink)

        sut.handleNotification(userInfo: ["bookId": "abc", "action": "restore_complete"])

        XCTAssertEqual(sut.pendingDeepLink, .book(id: "abc"))
    }

    func testHandleNotificationIgnoresUnrecognizedPayload() {
        let sut = DeepLinkManager()
        sut.handleNotification(userInfo: ["aps": ["alert": "hi"]])
        XCTAssertNil(sut.pendingDeepLink)
    }

    func testConsumeClearsPendingLink() {
        let sut = DeepLinkManager()
        sut.handleNotification(userInfo: ["bookId": "abc"])
        XCTAssertNotNil(sut.pendingDeepLink)

        sut.consume()

        XCTAssertNil(sut.pendingDeepLink)
    }
}
