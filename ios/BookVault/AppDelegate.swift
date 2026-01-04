//
//  AppDelegate.swift
//  BookVault
//
//  Created by Claude Code on 1/4/26.
//  Background Downloads Support
//

import UIKit

/// AppDelegate for handling background URLSession events
///
/// When a background download completes while the app is suspended or terminated,
/// iOS relaunches the app and calls `handleEventsForBackgroundURLSession`.
/// This delegate bridges that callback to the DownloadManager.
class AppDelegate: NSObject, UIApplicationDelegate {
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
}
