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
/// `@MainActor` because both `UIApplicationDelegate` and
/// `UNUserNotificationCenterDelegate` callbacks are delivered on the main
/// thread. Every method below already hopped to the main actor by hand, so this
/// states the existing contract rather than changing behavior.
@MainActor
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

// These are `nonisolated` because `UNUserNotificationCenterDelegate` is not
// itself `@MainActor`-annotated, so a `@MainActor` class cannot satisfy it
// directly. Both bodies already hop to the main actor explicitly for the work
// that needs it, so this is the same behavior stated precisely — not a
// loosening.
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show the banner/sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// The user tapped a notification — route to the deep link it carries.
    ///
    /// Note the completion handler is deliberately **not** marked `@Sendable`.
    /// Newer SDKs declare it that way, but the Xcode 16.2 SDK that CI pins does
    /// not, and adding the annotation makes this signature stop matching the
    /// protocol requirement there ("sendability of function types ... does not
    /// match requirement"). Leaving it off compiles on both.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Neither value can cross into the Task as-is: `userInfo` is
        // `[AnyHashable: Any]` and the handler is a non-`Sendable` closure. Both
        // are packaged here, synchronously, before the hop.
        //
        // No information is lost flattening `userInfo`:
        // `DeepLinkManager.deepLink(from:)` reads exactly one key, `bookId`, and
        // only as a `String`. Nested values like the APNs `aps` payload were
        // never consulted.
        let userInfo = response.notification.request.content.userInfo
        let payload = userInfo.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String {
                result[key] = value
            }
        }
        // A one-shot box carries the non-`Sendable` handler across the isolation
        // boundary. Safe because it is invoked exactly once: UserNotifications
        // vends one handler per delivery and permits calling it from any thread.
        let completion = UncheckedBox(completionHandler)
        Task { @MainActor in
            DeepLinkManager.shared.handleNotification(userInfo: payload)
            completion.value()
        }
    }
}
