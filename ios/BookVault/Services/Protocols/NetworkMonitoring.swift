//
//  NetworkMonitoring.swift
//  BookVault
//
//  Protocol for NetworkMonitor to enable testing with dependency injection.
//

import Foundation

/// Protocol for NetworkMonitor to enable testing
@MainActor
protocol NetworkMonitoring: ObservableObject {
    /// Whether the device is connected to the network
    var isConnected: Bool { get }

    /// Whether the current connection is expensive (cellular)
    var isExpensive: Bool { get }

    /// Current connection type (WiFi, Cellular, etc.)
    var connectionType: ConnectionType { get }

    /// Semantic alias for isConnected - clearer for offline mode logic
    var isOnline: Bool { get }

    /// Check if downloads are allowed based on current network and user settings
    var canDownload: Bool { get }

    /// Get reason why download is not allowed (for UI display)
    var downloadBlockedReason: String? { get }

    /// Force a refresh of network status
    func refreshStatus()

    /// Restart the network monitor completely
    func restartMonitor()

    /// Wait for network to become available
    /// - Parameter timeout: Maximum time to wait in seconds
    /// - Returns: True if network became available within timeout
    func waitForConnection(timeout: TimeInterval) async -> Bool
}
