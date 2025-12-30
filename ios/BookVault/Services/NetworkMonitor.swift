//
//  NetworkMonitor.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 7: Offline Downloads
//

import Foundation
import Network

/// Connection type enumeration
enum ConnectionType: String {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case unknown = "Unknown"
}

/// Monitors network connectivity for WiFi-only downloads
@MainActor
class NetworkMonitor: ObservableObject, NetworkMonitoring {
    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var isExpensive = false  // Cellular connections are "expensive"
    @Published var connectionType: ConnectionType = .unknown

    // MARK: - Private Properties

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.bookvault.networkmonitor", qos: .utility)

    // MARK: - Initialization

    private init() {
        setupMonitor()
    }

    deinit {
        // NWPathMonitor.cancel() is thread-safe, can be called from deinit
        monitor?.cancel()
    }

    // MARK: - Monitoring

    private func setupMonitor() {
        // Create a fresh monitor instance
        let newMonitor = NWPathMonitor()
        self.monitor = newMonitor

        // Capture self strongly in the handler since NetworkMonitor is a singleton
        // and we want it to stay alive for the app's lifetime
        newMonitor.pathUpdateHandler = { path in
            DebugLogger.network("NWPathMonitor callback received - status: \(path.status), interfaces: \(path.availableInterfaces.map { $0.type })")
            Task { @MainActor in
                NetworkMonitor.shared.handlePathUpdate(path)
            }
        }

        newMonitor.start(queue: queue)
        DebugLogger.network("Network monitoring started on queue: \(queue.label)")

        // Get initial state
        let currentPath = newMonitor.currentPath
        DebugLogger.network("Initial path status: \(currentPath.status)")
        handlePathUpdate(currentPath)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let wasConnected = isConnected
        let newConnected = path.status == .satisfied

        DebugLogger.network("handlePathUpdate - wasConnected: \(wasConnected), newConnected: \(newConnected), status: \(path.status)")

        isConnected = newConnected
        isExpensive = path.isExpensive
        connectionType = determineConnectionType(path)

        // Log significant changes
        if wasConnected != isConnected {
            if isConnected {
                DebugLogger.network("Network connected: \(connectionType.rawValue)")
            } else {
                DebugLogger.network("Network disconnected")
            }
        }
    }

    private func determineConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }
        return .unknown
    }

    // MARK: - Online Status

    /// Semantic alias for isConnected - clearer for offline mode logic
    var isOnline: Bool { isConnected }

    /// Force a refresh of network status by checking the current path
    /// Call this when user taps "Retry Connection" button
    func refreshStatus() {
        guard let monitor = monitor else {
            DebugLogger.network("refreshStatus called but monitor is nil - recreating")
            setupMonitor()
            return
        }
        let currentPath = monitor.currentPath
        DebugLogger.network("refreshStatus - manually checking currentPath: \(currentPath.status), interfaces: \(currentPath.availableInterfaces.map { $0.type })")
        handlePathUpdate(currentPath)
    }

    /// Restart the network monitor completely
    /// Use this if the monitor seems to have stopped receiving updates
    func restartMonitor() {
        DebugLogger.network("Restarting network monitor...")
        monitor?.cancel()
        monitor = nil
        setupMonitor()
    }

    // MARK: - Download Eligibility

    /// Check if downloads are allowed based on current network and user settings
    var canDownload: Bool {
        guard isConnected else {
            return false
        }

        let wifiOnly = UserDefaults.standard.bool(forKey: "downloadOnlyOnWiFi")

        if wifiOnly {
            return connectionType == .wifi
        }

        return true
    }

    /// Get reason why download is not allowed (for UI display)
    var downloadBlockedReason: String? {
        if !isConnected {
            return "No network connection"
        }

        let wifiOnly = UserDefaults.standard.bool(forKey: "downloadOnlyOnWiFi")

        if wifiOnly && connectionType != .wifi {
            return "Downloads require WiFi (change in Settings)"
        }

        return nil
    }

    /// Wait for network to become available
    /// Useful for retry logic after connection loss
    func waitForConnection(timeout: TimeInterval = 30) async -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if isConnected {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }

        return false
    }

    // MARK: - Testing Support

    #if DEBUG
    /// Simulate a network state change for testing purposes
    /// - Parameters:
    ///   - connected: Whether the network is connected
    ///   - expensive: Whether the connection is expensive (e.g., cellular)
    ///   - type: The type of connection
    /// - Note: This method is only available in DEBUG builds for testing
    func simulateNetworkState(connected: Bool, expensive: Bool = false, type: ConnectionType = .wifi) {
        DebugLogger.network("Simulating network state - connected: \(connected), expensive: \(expensive), type: \(type)")
        self.isConnected = connected
        self.isExpensive = expensive
        self.connectionType = type
    }

    /// Create a testable instance that doesn't start the real NWPathMonitor
    /// - Parameter userDefaults: UserDefaults to use for WiFi-only setting
    /// - Returns: A NetworkMonitor instance suitable for testing
    static func createForTesting(userDefaults: UserDefaults = .standard) -> NetworkMonitor {
        // Create instance without starting real monitor
        let instance = NetworkMonitor(forTesting: true)
        return instance
    }

    /// Private testing initializer that skips NWPathMonitor setup
    private convenience init(forTesting: Bool) {
        // Call the default init but we'll skip monitor setup
        self.init(skipMonitorSetup: true)
    }

    /// Private initializer that optionally skips monitor setup
    private init(skipMonitorSetup: Bool) {
        // Don't call setupMonitor() - for testing only
        DebugLogger.network("NetworkMonitor created for testing (monitor not started)")
    }
    #endif
}

