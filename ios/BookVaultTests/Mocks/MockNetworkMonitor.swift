//
//  MockNetworkMonitor.swift
//  BookVaultTests
//
//  Mock NetworkMonitor for testing - allows simulating network conditions.
//

import Combine
import Foundation
@testable import BookVault

/// Mock network monitor for testing
@MainActor
class MockNetworkMonitor: ObservableObject, NetworkMonitoring {
    // MARK: - Published Properties

    @Published var isConnected: Bool = true
    @Published var isExpensive: Bool = false
    @Published var connectionType: ConnectionType = .wifi

    // MARK: - Computed Properties

    var isOnline: Bool { isConnected }

    var canDownload: Bool {
        guard isConnected else { return false }
        if wifiOnlyEnabled {
            return connectionType == .wifi
        }
        return true
    }

    var downloadBlockedReason: String? {
        if !isConnected {
            return "No network connection"
        }
        if wifiOnlyEnabled, connectionType != .wifi {
            return "Downloads require WiFi (change in Settings)"
        }
        return nil
    }

    // MARK: - Mock Configuration

    var wifiOnlyEnabled: Bool = false
    var waitForConnectionShouldSucceed: Bool = true
    var refreshStatusCalled: Bool = false
    var restartMonitorCalled: Bool = false

    // MARK: - Protocol Implementation

    func refreshStatus() {
        refreshStatusCalled = true
    }

    func restartMonitor() {
        restartMonitorCalled = true
    }

    func waitForConnection(timeout _: TimeInterval) async -> Bool {
        if isConnected {
            return true
        }
        // Simulate waiting
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        return waitForConnectionShouldSucceed
    }

    // MARK: - Simulation Helpers

    func simulateWiFiConnection() {
        isConnected = true
        isExpensive = false
        connectionType = .wifi
    }

    func simulateCellularConnection() {
        isConnected = true
        isExpensive = true
        connectionType = .cellular
    }

    func simulateDisconnection() {
        isConnected = false
        isExpensive = false
        connectionType = .unknown
    }

    func simulateConnectionChange(connected: Bool, type: ConnectionType = .wifi) {
        isConnected = connected
        connectionType = type
        isExpensive = (type == .cellular)
    }

    // MARK: - Reset

    func reset() {
        isConnected = true
        isExpensive = false
        connectionType = .wifi
        wifiOnlyEnabled = false
        waitForConnectionShouldSucceed = true
        refreshStatusCalled = false
        restartMonitorCalled = false
    }
}
