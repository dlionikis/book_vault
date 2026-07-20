//
//  DeepLinkManager.swift
//  BookVault
//
//  Phase 7b: routing for push-notification taps.
//
//  When the user taps a restore-complete notification, iOS hands us the APNs
//  payload. The backend (lib/notification-service.ts) sends a top-level
//  `bookId` (UUID string) and `action: "restore_complete"`. This manager turns
//  that payload into a typed DeepLink and publishes it; ContentView observes
//  `pendingDeepLink` and presents the target book.
//

import Foundation

// MARK: - DeepLink

/// A destination the app can navigate to from outside the normal UI flow
/// (currently only push-notification taps).
enum DeepLink: Equatable {
    /// Show the detail page for a book (e.g. a restored audiobook is ready).
    case book(id: String)
}

// MARK: - DeepLinkManager

/// Holds a pending deep link for the UI to consume. Set from the AppDelegate on
/// a notification tap; cleared by the view once it has navigated.
@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    /// The pending destination, or nil when there's nothing to route to.
    /// ContentView observes this and navigates when it becomes non-nil.
    @Published var pendingDeepLink: DeepLink?

    init() {}

    /// Parse an APNs `userInfo` payload and, if it's a recognized deep link,
    /// stash it for the UI. Unknown payloads are ignored.
    ///
    /// Expected shape (matches the backend):
    /// `{ "aps": {...}, "bookId": "<uuid>", "action": "restore_complete" }`
    func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let link = Self.deepLink(from: userInfo) else {
            DebugLogger.info("Notification had no recognized deep link; ignoring")
            return
        }
        DebugLogger.info("Deep link from notification: \(link)")
        pendingDeepLink = link
    }

    /// Consume and clear the pending link (call after navigating).
    func consume() {
        pendingDeepLink = nil
    }

    /// Pure mapping from an APNs payload to a DeepLink (nil if unrecognized).
    /// Extracted as a static so it's trivially unit-testable without a device.
    static func deepLink(from userInfo: [AnyHashable: Any]) -> DeepLink? {
        // A valid, non-empty bookId is the only requirement to route to a book;
        // `action` is advisory (we only send restore_complete today).
        guard let bookId = userInfo["bookId"] as? String, !bookId.isEmpty else {
            return nil
        }
        return .book(id: bookId)
    }
}
