//
//  SystemKeychainTests.swift
//  BookVaultTests
//
//  Tests the REAL SystemKeychain against the simulator's keychain — no mock.
//  (The KeychainStoring mock exists for CONSUMERS of the keychain; testing the
//  keychain implementation itself requires the real Security framework.)
//
//  SystemKeychain identifies items by kSecAttrAccount alone (no service
//  attribute), so keys live in a single shared namespace. Every test uses a
//  unique key prefix and deletes its keys in tearDown to avoid cross-test
//  pollution and leftover items surviving between runs.
//

import XCTest

@testable import BookVault

final class SystemKeychainTests: XCTestCase {
    private var sut: SystemKeychain!
    private var keyPrefix: String!
    private var usedKeys: [String] = []

    override func setUp() {
        super.setUp()
        sut = SystemKeychain.shared
        keyPrefix = "test.\(UUID().uuidString)."
        usedKeys = []
    }

    override func tearDown() {
        for key in usedKeys {
            sut.delete(key: key)
        }
        usedKeys = []
        sut = nil
        keyPrefix = nil
        super.tearDown()
    }

    /// Register a namespaced key so tearDown cleans it up.
    private func key(_ name: String) -> String {
        let full = keyPrefix + name
        usedKeys.append(full)
        return full
    }

    // MARK: - Round-trip

    func testSaveThenLoadRoundTrips() throws {
        let k = key("roundtrip")
        try sut.save(key: k, value: "hello-value")
        XCTAssertEqual(sut.load(key: k), "hello-value")
    }

    // MARK: - Overwrite (the classic keychain bug: add-over-existing fails without delete)

    func testSaveOverExistingKeyOverwrites() throws {
        let k = key("overwrite")
        try sut.save(key: k, value: "first")
        try sut.save(key: k, value: "second")
        XCTAssertEqual(sut.load(key: k), "second",
                       "Saving over an existing key must replace the value, not fail or keep the old one")
    }

    // MARK: - Missing key

    func testLoadOfMissingKeyReturnsNil() {
        XCTAssertNil(sut.load(key: key("never-saved")))
    }

    // MARK: - Delete

    func testDeleteRemovesValue() throws {
        let k = key("delete")
        try sut.save(key: k, value: "to-delete")
        XCTAssertEqual(sut.load(key: k), "to-delete")

        sut.delete(key: k)
        XCTAssertNil(sut.load(key: k))
    }

    func testDeleteOfMissingKeyDoesNotThrow() {
        // delete is non-throwing (best-effort); calling it on a missing key
        // must be a safe no-op.
        sut.delete(key: key("missing-delete"))
        XCTAssertNil(sut.load(key: key("missing-delete")))
    }

    // MARK: - Encoding edge cases

    func testUnicodeValueRoundTrips() throws {
        let k = key("unicode")
        let value = "café ☕️ 日本語 — 🔐"
        try sut.save(key: k, value: value)
        XCTAssertEqual(sut.load(key: k), value)
    }

    func testLongValueRoundTrips() throws {
        let k = key("long")
        let value = String(repeating: "A1b2C3d4-", count: 5000) // ~45 KB
        try sut.save(key: k, value: value)
        XCTAssertEqual(sut.load(key: k), value)
    }
}
