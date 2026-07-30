//
//  NotificationRegistrar.swift
//  BookVault
//
//  Phase 7b: APNs registration + device-token upload.
//
//  Flow: request user authorization → register with APNs → AppDelegate receives
//  the device token → we POST it to /api/notifications/register so the backend
//  can create an SNS endpoint and push restore-complete notifications.
//

import Foundation
import UIKit
import UserNotifications

// MARK: - RemoteNotificationRegistering

/// Abstraction over `UIApplication.registerForRemoteNotifications()` so tests
/// can verify registration is triggered without touching the real app object.
@MainActor
protocol RemoteNotificationRegistering {
    func registerForRemoteNotifications()
}

extension UIApplication: RemoteNotificationRegistering {}

// MARK: - NotificationAuthorizing

/// Abstraction over `UNUserNotificationCenter` authorization so tests can drive
/// grant/deny outcomes deterministically.
protocol NotificationAuthorizing {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }
}

// MARK: - NotificationRegistrar

/// Coordinates push-notification permission and device-token registration.
@MainActor
final class NotificationRegistrar {
    static let shared = NotificationRegistrar()

    private let apiClient: any APIClientProtocol
    private let authorizer: NotificationAuthorizing
    private let application: any RemoteNotificationRegistering

    /// Guards against re-registering the same token repeatedly within a session.
    private var lastRegisteredToken: String?

    init(
        apiClient: any APIClientProtocol = APIClient.shared,
        authorizer: NotificationAuthorizing = SystemNotificationAuthorizer(),
        application: any RemoteNotificationRegistering = UIApplication.shared
    ) {
        self.apiClient = apiClient
        self.authorizer = authorizer
        self.application = application
    }

    /// Request authorization and, if granted, kick off APNs registration.
    /// Safe to call on every launch/login — the system dialog only appears once.
    /// The device token arrives asynchronously in the AppDelegate, which calls
    /// `registerToken(_:)`.
    func requestAuthorizationAndRegister() async {
        // The permission alert is a Springboard window that steals taps from the app,
        // making UI tests non-deterministic. Suppressing the request is more reliable
        // than racing an interruption monitor to dismiss it.
        if UITestEnvironment.shouldSkipPushAuthorization {
            DebugLogger.info("UI testing: skipping push authorization request")
            return
        }

        do {
            let granted = try await authorizer.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                DebugLogger.info("Push authorization denied by user")
                return
            }
            application.registerForRemoteNotifications()
            DebugLogger.info("Push authorized; requested APNs registration")
        } catch {
            DebugLogger.error("Push authorization request failed", error: error)
        }
    }

    /// Convert the raw APNs device-token data to a hex string and upload it.
    /// Called by the AppDelegate from
    /// `didRegisterForRemoteNotificationsWithDeviceToken`.
    func registerToken(_ deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        await registerTokenString(hex)
    }

    /// Upload an already-formatted hex token. Deduplicates within the session so
    /// we don't POST the same token repeatedly.
    func registerTokenString(_ hex: String) async {
        guard hex != lastRegisteredToken else {
            DebugLogger.verbose("Device token unchanged; skipping re-registration")
            return
        }
        do {
            _ = try await apiClient.registerDeviceToken(deviceToken: hex)
            lastRegisteredToken = hex
            DebugLogger.info("Device token registered with backend")
        } catch {
            // Non-fatal: push just won't work until the next successful attempt.
            DebugLogger.error("Failed to register device token", error: error)
        }
    }

    /// Called by the AppDelegate when APNs registration fails (e.g. no network,
    /// simulator without a paired push environment). Non-fatal.
    func registrationFailed(_ error: Error) {
        DebugLogger.error("APNs registration failed", error: error)
    }
}
