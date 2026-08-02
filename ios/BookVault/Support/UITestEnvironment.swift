//
//  UITestEnvironment.swift
//  BookVault
//
//  Launch-argument hooks that put the app in a deterministic state for UI tests.
//

import Foundation

/// Detects the `--uitesting` launch argument and exposes the resets UI tests need.
///
/// UI tests must start from a known state. Two behaviours otherwise make
/// assertions unreliable:
///
/// - A restored keychain session skips the login screen, so a test that expects
///   to log in finds the tab bar instead.
/// - `ContentView` auto-loads the most recently played book into the mini player
///   on launch, so "the mini player appears after playback starts" would pass
///   before any playback happened.
///
/// Both are suppressed only under the launch argument, so shipping behaviour is
/// untouched. See docs/plans/ios-ui-testing-plan.md.
enum UITestEnvironment {
    /// True when the app was launched by the XCUITest suite.
    static let isActive = ProcessInfo.processInfo.arguments.contains("--uitesting")

    /// Skip restoring a keychain session so the login screen is always shown.
    static var shouldResetSession: Bool { isActive }

    /// Skip the launch-time mini-player auto-load so playback assertions are real.
    static var shouldSkipInitialBookLoad: Bool { isActive }

    /// Skip the push-authorization request. Its system alert is a Springboard window
    /// that steals taps from the app, so leaving it enabled makes every flow flaky.
    static var shouldSkipPushAuthorization: Bool { isActive }

    /// Drop the autofill `textContentType` from the login fields.
    ///
    /// `.username`/`.password` are correct for shipping - they enable password
    /// autofill - but they make iOS present a "Save Password?" sheet after a
    /// successful login. That sheet lives in a separate window above the app and
    /// blocks interaction with every element beneath it, and it cannot be reliably
    /// dismissed from the test process: tapping "Not Now" synthesizes an event but the
    /// sheet stays up. Suppressing the trigger is deterministic; dismissing it is not.
    static var shouldDisablePasswordAutofill: Bool { isActive }

    /// Render `NowPlayingView` against mock data as the root view, bypassing
    /// login and playback.
    ///
    /// The player's layout can only really be checked by looking at it, and
    /// reaching it normally needs a backend, a session and an audio stream.
    /// This puts the real view on screen with no network so a test can
    /// screenshot it. Gated on the launch argument, so shipping is untouched.
    static var shouldShowNowPlayingHarness: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("--harness-now-playing")
    }
}
