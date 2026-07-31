//
//  NetworkMonitorTests.swift
//  BookVaultTests
//
//  Unit tests for NetworkMonitor.
//

import Combine
import XCTest
@testable import BookVault

@MainActor
final class NetworkMonitorTests: XCTestCase {
    var sut: MockNetworkMonitor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        sut = MockNetworkMonitor()
        cancellables = []
    }

    override func tearDown() async throws {
        cancellables = nil
        sut = nil
    }

    // MARK: - Connection Status Tests

    func testInitialConnectionStatusIsConnected() {
        // Given: A fresh mock network monitor

        // Then: Should be connected by default
        XCTAssertTrue(sut.isConnected)
        XCTAssertTrue(sut.isOnline)
    }

    func testInitialConnectionTypeIsWiFi() {
        // Given: A fresh mock network monitor

        // Then: Should be on WiFi by default
        XCTAssertEqual(sut.connectionType, .wifi)
    }

    // MARK: - Simulate WiFi Connection Tests

    func testSimulateWiFiConnection() {
        // Given: Disconnected state
        sut.simulateDisconnection()
        XCTAssertFalse(sut.isConnected)

        // When: Simulating WiFi connection
        sut.simulateWiFiConnection()

        // Then: Should be connected via WiFi
        XCTAssertTrue(sut.isConnected)
        XCTAssertEqual(sut.connectionType, .wifi)
        XCTAssertFalse(sut.isExpensive)
    }

    // MARK: - Simulate Cellular Connection Tests

    func testSimulateCellularConnection() {
        // Given: WiFi connected state
        sut.simulateWiFiConnection()

        // When: Simulating cellular connection
        sut.simulateCellularConnection()

        // Then: Should be connected via cellular and marked as expensive
        XCTAssertTrue(sut.isConnected)
        XCTAssertEqual(sut.connectionType, .cellular)
        XCTAssertTrue(sut.isExpensive)
    }

    // MARK: - Simulate Disconnection Tests

    func testSimulateDisconnection() {
        // Given: Connected state
        XCTAssertTrue(sut.isConnected)

        // When: Simulating disconnection
        sut.simulateDisconnection()

        // Then: Should be disconnected
        XCTAssertFalse(sut.isConnected)
        XCTAssertFalse(sut.isOnline)
        XCTAssertEqual(sut.connectionType, .unknown)
    }

    // MARK: - WiFi-Only Download Tests

    func testCanDownloadWhenOnWiFi() {
        // Given: Connected via WiFi with WiFi-only enabled
        sut.simulateWiFiConnection()
        sut.wifiOnlyEnabled = true

        // Then: Should be able to download
        XCTAssertTrue(sut.canDownload)
    }

    func testCannotDownloadWhenOnCellularWithWiFiOnly() {
        // Given: Connected via cellular with WiFi-only enabled
        sut.simulateCellularConnection()
        sut.wifiOnlyEnabled = true

        // Then: Should not be able to download
        XCTAssertFalse(sut.canDownload)
    }

    func testCanDownloadOnCellularWhenWiFiOnlyDisabled() {
        // Given: Connected via cellular with WiFi-only disabled
        sut.simulateCellularConnection()
        sut.wifiOnlyEnabled = false

        // Then: Should be able to download
        XCTAssertTrue(sut.canDownload)
    }

    func testCannotDownloadWhenDisconnected() {
        // Given: Disconnected
        sut.simulateDisconnection()

        // Then: Should not be able to download
        XCTAssertFalse(sut.canDownload)
    }

    // MARK: - Download Blocked Reason Tests

    func testDownloadBlockedReasonWhenDisconnected() {
        // Given: Disconnected
        sut.simulateDisconnection()

        // Then: Should have appropriate blocked reason
        XCTAssertNotNil(sut.downloadBlockedReason)
        XCTAssertEqual(sut.downloadBlockedReason, "No network connection")
    }

    func testDownloadBlockedReasonOnCellularWithWiFiOnly() {
        // Given: On cellular with WiFi-only enabled
        sut.simulateCellularConnection()
        sut.wifiOnlyEnabled = true

        // Then: Should have appropriate blocked reason
        XCTAssertNotNil(sut.downloadBlockedReason)
        XCTAssertTrue(sut.downloadBlockedReason?.contains("WiFi") ?? false)
    }

    func testNoBlockedReasonWhenCanDownload() {
        // Given: Connected via WiFi
        sut.simulateWiFiConnection()
        sut.wifiOnlyEnabled = false

        // Then: Should have no blocked reason
        XCTAssertNil(sut.downloadBlockedReason)
    }

    // MARK: - Refresh Status Tests

    func testRefreshStatusRecordsCall() {
        // Given: A fresh mock
        XCTAssertFalse(sut.refreshStatusCalled)

        // When: refreshStatus is called
        sut.refreshStatus()

        // Then: Call should be recorded
        XCTAssertTrue(sut.refreshStatusCalled)
    }

    // MARK: - Restart Monitor Tests

    func testRestartMonitorRecordsCall() {
        // Given: A fresh mock
        XCTAssertFalse(sut.restartMonitorCalled)

        // When: restartMonitor is called
        sut.restartMonitor()

        // Then: Call should be recorded
        XCTAssertTrue(sut.restartMonitorCalled)
    }

    // MARK: - Wait For Connection Tests

    func testWaitForConnectionReturnsTrueWhenConnected() async {
        // Given: Connected
        sut.isConnected = true

        // When: Waiting for connection
        let result = await sut.waitForConnection(timeout: 1.0)

        // Then: Should return true immediately
        XCTAssertTrue(result)
    }

    func testWaitForConnectionReturnsConfiguredResult() async {
        // Given: Disconnected but configured to succeed
        sut.isConnected = false
        sut.waitForConnectionShouldSucceed = true

        // When: Waiting for connection
        let result = await sut.waitForConnection(timeout: 1.0)

        // Then: Should return configured result
        XCTAssertTrue(result)
    }

    func testWaitForConnectionReturnsFalseWhenConfigured() async {
        // Given: Disconnected and configured to fail
        sut.isConnected = false
        sut.waitForConnectionShouldSucceed = false

        // When: Waiting for connection
        let result = await sut.waitForConnection(timeout: 1.0)

        // Then: Should return false
        XCTAssertFalse(result)
    }

    // MARK: - Connection Type Mutual Exclusivity Tests

    func testWiFiAndCellularAreMutuallyExclusive() {
        // Given: Connected via WiFi
        sut.simulateWiFiConnection()

        // Then: Should not be on cellular
        XCTAssertEqual(sut.connectionType, .wifi)
        XCTAssertNotEqual(sut.connectionType, .cellular)

        // Given: Switch to cellular
        sut.simulateCellularConnection()

        // Then: Should not be on WiFi
        XCTAssertEqual(sut.connectionType, .cellular)
        XCTAssertNotEqual(sut.connectionType, .wifi)
    }

    // MARK: - Reset Tests

    func testResetRestoresDefaultState() {
        // Given: Modified state
        sut.simulateCellularConnection()
        sut.wifiOnlyEnabled = true
        sut.refreshStatus()
        sut.restartMonitor()

        // When: Reset is called
        sut.reset()

        // Then: Should restore default state
        XCTAssertTrue(sut.isConnected)
        XCTAssertEqual(sut.connectionType, .wifi)
        XCTAssertFalse(sut.isExpensive)
        XCTAssertFalse(sut.wifiOnlyEnabled)
        XCTAssertFalse(sut.refreshStatusCalled)
        XCTAssertFalse(sut.restartMonitorCalled)
    }

    // MARK: - isOnline Alias Tests

    func testIsOnlineMatchesIsConnected() {
        // Given: Connected
        sut.isConnected = true
        XCTAssertEqual(sut.isOnline, sut.isConnected)

        // Given: Disconnected
        sut.isConnected = false
        XCTAssertEqual(sut.isOnline, sut.isConnected)
    }

    // MARK: - Real NetworkMonitor Smoke Tests

    func testRealNetworkMonitorExists() {
        // This is a smoke test to verify the real singleton exists
        let realMonitor = NetworkMonitor.shared
        XCTAssertNotNil(realMonitor)
    }
}
