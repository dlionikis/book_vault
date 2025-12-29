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
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var isExpensive = false  // Cellular connections are "expensive"
    @Published var connectionType: ConnectionType = .unknown

    // MARK: - Private Properties

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.bookvault.networkmonitor", qos: .utility)

    // MARK: - Initialization

    private init() {
        startMonitoring()
    }

    deinit {
        // NWPathMonitor.cancel() is thread-safe, can be called from deinit
        monitor.cancel()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: queue)
        DebugLogger.network("Network monitoring started")
    }

    private func handlePathUpdate(_ path: NWPath) {
        let wasConnected = isConnected

        isConnected = path.status == .satisfied
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
}

