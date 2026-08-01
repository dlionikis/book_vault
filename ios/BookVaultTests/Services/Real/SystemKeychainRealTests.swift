//
//  SystemKeychainRealTests.swift
//  BookVaultTests
//
//  Tests the real keychain store against the system Security framework.
//
//  The load-bearing assertion here is the accessibility attribute. Items
//  written without one default to `kSecAttrAccessibleWhenUnlocked`, which makes
//  them unreadable the instant the screen locks. Because this app streams audio
//  in the background, that default broke playback on lock and then showed
//  "Your session has expired" on the next foreground. Nothing in the app's own
//  behavior reveals the attribute — only reading it back from the keychain
//  does, which is why these tests exist.
//

import Security
import XCTest

@testable import BookVault

final class SystemKeychainRealTests: XCTestCase {
    private let sut = SystemKeychain.shared

    /// Namespaced per run so these tests can never collide with a real session's
    /// keys, and so a failure cannot leave the app logged out on a dev device.
    private var testKey: String!

    override func setUp() async throws {
        testKey = "com.bookvault.tests.\(UUID().uuidString)"
        try skipIfKeychainUnavailable()
    }

    /// Skip when the test runner has no keychain-access entitlement.
    ///
    /// `validate:ios` runs unit tests with `CODE_SIGNING_ALLOWED=NO`, which
    /// strips entitlements, so every `SecItemAdd` fails with `-34018`
    /// (`errSecMissingEntitlement`) — a property of the build configuration,
    /// not of the code under test. The same trap is documented for the UI-test
    /// step in `scripts/ios-validate.sh`.
    ///
    /// These assertions still run in any signed context (Xcode locally, the
    /// UI-test scheme), which is where they can actually observe the keychain.
    /// The lock-state *behavior* they guard is additionally covered without a
    /// real keychain by `MockKeychain.isLocked` in `AuthManagerRealTests` and
    /// `AuthenticatedResourceLoaderTests`.
    private func skipIfKeychainUnavailable() throws {
        let probeKey = "com.bookvault.tests.entitlement-probe"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: probeKey,
            kSecValueData as String: Data("probe".utf8)
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        SecItemDelete(query as CFDictionary)

        try XCTSkipIf(
            status == errSecMissingEntitlement,
            "Keychain unavailable: test runner built without entitlements (CODE_SIGNING_ALLOWED=NO)"
        )
    }

    override func tearDown() async throws {
        sut.delete(key: testKey)
        testKey = nil
    }

    // MARK: - Accessibility (the background-playback fix)

    /// Read the raw `kSecAttrAccessible` attribute back from the keychain.
    private func storedAccessibility(for key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess, "Item should exist")

        let attributes = try XCTUnwrap(result as? [String: Any])
        return try XCTUnwrap(attributes[kSecAttrAccessible as String] as? String)
    }

    /// The core regression test: tokens must survive a locked screen.
    func testSavedItemIsAccessibleAfterFirstUnlock() throws {
        try sut.save(key: testKey, value: "token")

        XCTAssertEqual(
            try storedAccessibility(for: testKey),
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            "Tokens must stay readable while the device is locked, or background playback stops"
        )
    }

    /// Overwriting must not silently retain a pre-fix `WhenUnlocked` attribute.
    /// `SecItemAdd` does not update an existing item's accessibility, so the
    /// save path has to replace the item — this pins that behavior.
    func testOverwriteMigratesAccessibilityFromLegacyValue() throws {
        // Given - an item written the old way (no accessibility ⇒ WhenUnlocked)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: testKey!,
            kSecValueData as String: Data("legacy".utf8)
        ]
        SecItemDelete(legacyQuery as CFDictionary)
        XCTAssertEqual(SecItemAdd(legacyQuery as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(
            try storedAccessibility(for: testKey),
            kSecAttrAccessibleWhenUnlocked as String,
            "Precondition: the legacy item has the broken attribute"
        )

        // When - the app saves over it (a login or token refresh)
        try sut.save(key: testKey, value: "new-token")

        // Then - the item is migrated, not left with the old attribute
        XCTAssertEqual(
            try storedAccessibility(for: testKey),
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(sut.load(key: testKey), "new-token")
    }

    // MARK: - Read semantics

    func testReadReturnsFoundForStoredValue() throws {
        try sut.save(key: testKey, value: "stored")
        XCTAssertEqual(sut.read(key: testKey), .found("stored"))
    }

    /// A missing item must report `.notFound`, never `.locked` — the two drive
    /// opposite session decisions.
    func testReadReturnsNotFoundForMissingKey() {
        XCTAssertEqual(sut.read(key: testKey), .notFound)
        XCTAssertFalse(sut.read(key: testKey).isLocked)
    }

    func testLoadAndReadAgree() throws {
        try sut.save(key: testKey, value: "same")
        XCTAssertEqual(sut.load(key: testKey), sut.read(key: testKey).value)
    }

    func testSaveOverwritesExistingValue() throws {
        try sut.save(key: testKey, value: "first")
        try sut.save(key: testKey, value: "second")
        XCTAssertEqual(sut.load(key: testKey), "second")
    }

    func testDeleteRemovesValue() throws {
        try sut.save(key: testKey, value: "doomed")
        sut.delete(key: testKey)
        XCTAssertEqual(sut.read(key: testKey), .notFound)
    }

    func testDeleteIsIdempotent() {
        sut.delete(key: testKey)
        sut.delete(key: testKey)
        XCTAssertEqual(sut.read(key: testKey), .notFound)
    }
}
