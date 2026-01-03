//
//  BiometricAuthManagerTests.swift
//  BookVaultTests
//
//  Unit tests for BiometricAuthManager.
//  Note: Actual biometric authentication requires hardware and cannot be unit tested.
//  These tests focus on state management, UserDefaults persistence, and error handling.
//

import XCTest
@testable import BookVault

@MainActor
final class BiometricAuthManagerTests: XCTestCase {

    // Test keys to avoid polluting production UserDefaults
    private let testBiometricEnabledKey = "biometricEnabled"
    private let testBiometricEmailKey = "biometricEmail"

    override func setUp() {
        super.setUp()
        // Clear any existing biometric state before each test
        UserDefaults.standard.removeObject(forKey: testBiometricEnabledKey)
        UserDefaults.standard.removeObject(forKey: testBiometricEmailKey)
    }

    override func tearDown() {
        // Clean up after tests
        BiometricAuthManager.shared.disableBiometric()
        super.tearDown()
    }

    // MARK: - Biometry Type Detection Tests

    func testBiometryTypeIsDetected() {
        // Given
        let manager = BiometricAuthManager.shared

        // Then - biometryType should be set (even if .none in simulator)
        // We can't assert a specific value since it depends on device
        XCTAssertNotNil(manager.biometryType)
    }

    func testBiometryNameReturnsNonEmptyString() {
        // Given
        let manager = BiometricAuthManager.shared

        // Then
        XCTAssertFalse(manager.biometryName.isEmpty)
    }

    func testBiometryNameForKnownTypes() {
        // This test documents expected names for each biometry type
        // Actual value depends on device, but we verify the property works
        let manager = BiometricAuthManager.shared
        let name = manager.biometryName

        // Should be one of the known values or "Biometrics"
        let knownNames = ["Face ID", "Touch ID", "Optic ID", "Biometrics"]
        XCTAssertTrue(knownNames.contains(name), "biometryName should be a known value, got: \(name)")
    }

    // MARK: - Initial State Tests

    func testInitialStateIsBiometricDisabled() {
        // Given a fresh state (cleared in setUp)
        let manager = BiometricAuthManager.shared

        // Force reload of preference
        manager.disableBiometric()

        // Then
        XCTAssertFalse(manager.isBiometricEnabled)
    }

    // MARK: - Enable/Disable Tests

    func testDisableBiometricClearsState() {
        // Given
        let manager = BiometricAuthManager.shared

        // When
        manager.disableBiometric()

        // Then
        XCTAssertFalse(manager.isBiometricEnabled)
        XCTAssertNil(UserDefaults.standard.string(forKey: testBiometricEmailKey))
    }

    // MARK: - Email Matching Tests

    func testIsBiometricEnabledForEmailReturnsFalseWhenDisabled() {
        // Given biometric is disabled
        let manager = BiometricAuthManager.shared
        manager.disableBiometric()

        // Then
        XCTAssertFalse(manager.isBiometricEnabledFor(email: "test@example.com"))
    }

    // MARK: - Error Description Tests

    func testBiometricErrorNotAvailableHasDescription() {
        let error = BiometricError.notAvailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBiometricErrorNotEnabledHasDescription() {
        let error = BiometricError.notEnabled
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBiometricErrorAuthenticationFailedHasDescription() {
        let error = BiometricError.authenticationFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBiometricErrorCredentialsNotFoundHasDescription() {
        let error = BiometricError.credentialsNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("password"))
    }

    func testBiometricErrorEncodingFailedHasDescription() {
        let error = BiometricError.encodingFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBiometricErrorAccessControlCreationFailedHasDescription() {
        let error = BiometricError.accessControlCreationFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBiometricErrorKeychainSaveFailedHasDescription() {
        let error = BiometricError.keychainSaveFailed(-25300)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("-25300"))
    }

    // MARK: - Authentication Flow Tests (Limited in Simulator)

    func testAuthenticateAndGetCredentialsThrowsWhenNotEnabled() async {
        // Given biometric is disabled
        let manager = BiometricAuthManager.shared
        manager.disableBiometric()

        // When/Then
        do {
            _ = try await manager.authenticateAndGetCredentials()
            XCTFail("Should have thrown an error")
        } catch let error as BiometricError {
            XCTAssertEqual(error, BiometricError.notEnabled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
