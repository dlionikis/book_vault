//
//  NetworkMonitorRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 1: Real Services Testing - NetworkMonitor
//

import XCTest
@testable import BookVault

@MainActor
final class NetworkMonitorRealTests: XCTestCase {
    // MARK: - Properties

    private var networkMonitor: NetworkMonitor!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "NetworkMonitorTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        networkMonitor = NetworkMonitor.createForTesting(userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        networkMonitor = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - ConnectionType Tests

    func testConnectionTypeRawValues() {
        XCTAssertEqual(ConnectionType.wifi.rawValue, "WiFi")
        XCTAssertEqual(ConnectionType.cellular.rawValue, "Cellular")
        XCTAssertEqual(ConnectionType.ethernet.rawValue, "Ethernet")
        XCTAssertEqual(ConnectionType.unknown.rawValue, "Unknown")
    }

    // MARK: - Initial State Tests

    func testInitialState_IsDisconnected() {
        // Test instance should start disconnected (no real monitor)
        XCTAssertFalse(networkMonitor.isConnected)
    }

    func testInitialState_IsNotExpensive() {
        XCTAssertFalse(networkMonitor.isExpensive)
    }

    func testInitialState_ConnectionTypeIsUnknown() {
        XCTAssertEqual(networkMonitor.connectionType, .unknown)
    }

    // MARK: - isOnline Alias Tests

    func testIsOnline_MatchesIsConnected() {
        networkMonitor.simulateNetworkState(connected: true)
        XCTAssertEqual(networkMonitor.isOnline, networkMonitor.isConnected)

        networkMonitor.simulateNetworkState(connected: false)
        XCTAssertEqual(networkMonitor.isOnline, networkMonitor.isConnected)
    }

    // MARK: - State Simulation Tests

    func testSimulateNetworkState_WiFiConnected() {
        // When: Simulating WiFi connected state
        networkMonitor.simulateNetworkState(connected: true, expensive: false, type: .wifi)

        // Then: State reflects WiFi connection
        XCTAssertTrue(networkMonitor.isConnected)
        XCTAssertFalse(networkMonitor.isExpensive)
        XCTAssertEqual(networkMonitor.connectionType, .wifi)
    }

    func testSimulateNetworkState_CellularConnected() {
        // When: Simulating cellular connected state
        networkMonitor.simulateNetworkState(connected: true, expensive: true, type: .cellular)

        // Then: State reflects cellular connection
        XCTAssertTrue(networkMonitor.isConnected)
        XCTAssertTrue(networkMonitor.isExpensive)
        XCTAssertEqual(networkMonitor.connectionType, .cellular)
    }

    func testSimulateNetworkState_EthernetConnected() {
        // When: Simulating ethernet connected state
        networkMonitor.simulateNetworkState(connected: true, expensive: false, type: .ethernet)

        // Then: State reflects ethernet connection
        XCTAssertTrue(networkMonitor.isConnected)
        XCTAssertFalse(networkMonitor.isExpensive)
        XCTAssertEqual(networkMonitor.connectionType, .ethernet)
    }

    func testSimulateNetworkState_Disconnected() {
        // Given: Previously connected
        networkMonitor.simulateNetworkState(connected: true, type: .wifi)

        // When: Simulating disconnected state
        networkMonitor.simulateNetworkState(connected: false, type: .unknown)

        // Then: State reflects disconnection
        XCTAssertFalse(networkMonitor.isConnected)
        XCTAssertEqual(networkMonitor.connectionType, .unknown)
    }

    // MARK: - canDownload Tests

    func testCanDownload_WhenDisconnected_ReturnsFalse() {
        networkMonitor.simulateNetworkState(connected: false)
        XCTAssertFalse(networkMonitor.canDownload)
    }

    func testCanDownload_WhenConnectedOnWiFi_ReturnsTrue() {
        networkMonitor.simulateNetworkState(connected: true, type: .wifi)
        testDefaults.set(false, forKey: "downloadOnlyOnWiFi")
        XCTAssertTrue(networkMonitor.canDownload)
    }

    func testCanDownload_WhenConnectedOnCellular_WiFiOnlyDisabled_ReturnsTrue() {
        networkMonitor.simulateNetworkState(connected: true, type: .cellular)
        testDefaults.set(false, forKey: "downloadOnlyOnWiFi")
        XCTAssertTrue(networkMonitor.canDownload)
    }

    func testCanDownload_WhenConnectedOnCellular_WiFiOnlyEnabled_ReturnsFalse() {
        networkMonitor.simulateNetworkState(connected: true, type: .cellular)
        UserDefaults.standard.set(true, forKey: "downloadOnlyOnWiFi")
        defer { UserDefaults.standard.removeObject(forKey: "downloadOnlyOnWiFi") }

        XCTAssertFalse(networkMonitor.canDownload)
    }

    func testCanDownload_WhenConnectedOnWiFi_WiFiOnlyEnabled_ReturnsTrue() {
        networkMonitor.simulateNetworkState(connected: true, type: .wifi)
        UserDefaults.standard.set(true, forKey: "downloadOnlyOnWiFi")
        defer { UserDefaults.standard.removeObject(forKey: "downloadOnlyOnWiFi") }

        XCTAssertTrue(networkMonitor.canDownload)
    }

    // MARK: - downloadBlockedReason Tests

    func testDownloadBlockedReason_WhenDisconnected_ReturnsNoConnection() {
        networkMonitor.simulateNetworkState(connected: false)
        XCTAssertEqual(networkMonitor.downloadBlockedReason, "No network connection")
    }

    func testDownloadBlockedReason_WhenConnectedOnWiFi_ReturnsNil() {
        networkMonitor.simulateNetworkState(connected: true, type: .wifi)
        XCTAssertNil(networkMonitor.downloadBlockedReason)
    }

    func testDownloadBlockedReason_WhenCellularAndWiFiOnly_ReturnsWiFiRequired() {
        networkMonitor.simulateNetworkState(connected: true, type: .cellular)
        UserDefaults.standard.set(true, forKey: "downloadOnlyOnWiFi")
        defer { UserDefaults.standard.removeObject(forKey: "downloadOnlyOnWiFi") }

        XCTAssertEqual(networkMonitor.downloadBlockedReason, "Downloads require WiFi (change in Settings)")
    }

    func testDownloadBlockedReason_WhenCellularAndWiFiOnlyDisabled_ReturnsNil() {
        networkMonitor.simulateNetworkState(connected: true, type: .cellular)
        UserDefaults.standard.set(false, forKey: "downloadOnlyOnWiFi")
        defer { UserDefaults.standard.removeObject(forKey: "downloadOnlyOnWiFi") }

        XCTAssertNil(networkMonitor.downloadBlockedReason)
    }

    // MARK: - waitForConnection Tests

    func testWaitForConnection_WhenAlreadyConnected_ReturnsImmediately() async {
        // Given: Already connected
        networkMonitor.simulateNetworkState(connected: true)

        // When: Waiting for connection
        let startTime = Date()
        let result = await networkMonitor.waitForConnection(timeout: 5)
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Returns immediately with true
        XCTAssertTrue(result)
        XCTAssertLessThan(elapsed, 1.0) // Should return almost immediately
    }

    func testWaitForConnection_WhenDisconnected_TimesOut() async {
        // Given: Disconnected
        networkMonitor.simulateNetworkState(connected: false)

        // When: Waiting for connection with short timeout
        let startTime = Date()
        let result = await networkMonitor.waitForConnection(timeout: 1)
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Times out and returns false
        XCTAssertFalse(result)
        XCTAssertGreaterThanOrEqual(elapsed, 0.9) // Should wait at least close to timeout
    }

    // MARK: - State Transition Tests

    func testStateTransition_FromDisconnectedToConnected() {
        // Given: Disconnected state
        networkMonitor.simulateNetworkState(connected: false)
        XCTAssertFalse(networkMonitor.isConnected)

        // When: Transitioning to connected
        networkMonitor.simulateNetworkState(connected: true, type: .wifi)

        // Then: State is updated
        XCTAssertTrue(networkMonitor.isConnected)
        XCTAssertEqual(networkMonitor.connectionType, .wifi)
    }

    func testStateTransition_FromWiFiToCellular() {
        // Given: Connected on WiFi
        networkMonitor.simulateNetworkState(connected: true, expensive: false, type: .wifi)
        XCTAssertFalse(networkMonitor.isExpensive)

        // When: Transitioning to cellular
        networkMonitor.simulateNetworkState(connected: true, expensive: true, type: .cellular)

        // Then: State reflects cellular
        XCTAssertTrue(networkMonitor.isConnected)
        XCTAssertTrue(networkMonitor.isExpensive)
        XCTAssertEqual(networkMonitor.connectionType, .cellular)
    }

    func testStateTransition_MultipleRapidChanges() {
        // Simulate rapid network changes
        networkMonitor.simulateNetworkState(connected: true, type: .wifi)
        networkMonitor.simulateNetworkState(connected: true, type: .cellular)
        networkMonitor.simulateNetworkState(connected: false)
        networkMonitor.simulateNetworkState(connected: true, type: .ethernet)

        // Final state should reflect last change
        XCTAssertTrue(networkMonitor.isConnected)
        XCTAssertEqual(networkMonitor.connectionType, .ethernet)
    }

    // MARK: - Protocol Conformance Tests

    func testNetworkMonitoringProtocolConformance() {
        // Verify NetworkMonitor conforms to NetworkMonitoring protocol
        let monitor: any NetworkMonitoring = networkMonitor
        XCTAssertNotNil(monitor)

        // Test protocol properties are accessible
        _ = monitor.isConnected
        _ = monitor.isExpensive
        _ = monitor.connectionType
        _ = monitor.isOnline
        _ = monitor.canDownload
        _ = monitor.downloadBlockedReason
    }
}
