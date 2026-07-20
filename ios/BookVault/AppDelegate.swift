//
//  AppDelegate.swift
//  BookVault
//
//  Created by Claude Code on 1/4/26.
//  Background Downloads Support
//

import UIKit
import UserNotifications

/// AppDelegate for background URLSession events (background downloads) and
/// push notifications (Phase 7b).
///
/// Background downloads: when one completes while the app is suspended or
/// terminated, iOS relaunches the app and calls
/// `handleEventsForBackgroundURLSession`, which we bridge to the DownloadManager.
///
/// Push: we receive the APNs device token here and hand it to the
/// NotificationRegistrar; notification taps are routed to the DeepLinkManager.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Receive notification taps (and foreground presentation) via this delegate.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called when background URLSession events need to be handled
    ///
    /// iOS calls this when:
    /// - A background download completes while app was suspended
    /// - A background download completes after app was terminated
    /// - The app needs to process completed background transfers
    ///
    /// - Parameters:
    ///   - application: The singleton app object
    ///   - identifier: The background session identifier that has events
    ///   - completionHandler: Must be called after processing all events
    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DebugLogger.info("Background session events for: \(identifier)")

        Task { @MainActor in
            DownloadManager.shared.handleBackgroundSessionEvents(
                identifier: identifier,
                completionHandler: completionHandler
            )
        }
    }

    // MARK: - Push Notifications (Phase 7b)

    /// APNs handed us a device token — upload it so the backend can push to us.
    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await NotificationRegistrar.shared.registerToken(deviceToken)
        }
    }

    /// APNs registration failed (no network, simulator without a push
    /// environment, etc.). Non-fatal — the rest of the app works.
    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationRegistrar.shared.registrationFailed(error)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show the banner/sound even when the app is in the foreground.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// The user tapped a notification — route to the deep link it carries.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            DeepLinkManager.shared.handleNotification(userInfo: userInfo)
            completionHandler()
        }
    }
}
