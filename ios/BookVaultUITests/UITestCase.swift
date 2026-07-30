//
//  UITestCase.swift
//  BookVaultUITests
//
//  Base class for XCUITest flows.
//

import XCTest

/// Shared setup for UI tests: launches the app in a deterministic state and
/// provides helpers the flows need.
///
/// Every test starts from the login screen — `--uitesting` makes the app clear any
/// keychain session and skip the launch-time mini-player auto-load. See
/// `UITestEnvironment` in the app target.
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Generous enough for a cold launch and a network round trip on CI, short
    /// enough that a genuine failure does not stall the suite.
    static let defaultTimeout: TimeInterval = 20

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A failed assertion should stop the flow: later steps in a UI flow depend
        // on earlier ones, so continuing produces cascading noise.
        continueAfterFailure = false

        // No interruption monitor for the push-permission alert: the app skips the
        // authorization request entirely under `--uitesting`, so the alert never
        // appears. Suppressing it is deterministic; racing a monitor to dismiss a
        // Springboard window is not.
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Waits for an element and fails with a useful message if it never appears.
    @discardableResult
    func require(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = UITestCase.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(description) to appear within \(timeout)s",
            file: file,
            line: line
        )
        return element
    }

    /// Logs in with the development credentials and waits for the tab bar.
    ///
    /// Requires a running backend with a seeded user (`npm run dev` +
    /// `npm run e2e:seed`).
    func logIn(username: String = "testuser", password: String = "password123") {
        let usernameField = require(
            app.textFields[A11yID.Login.username],
            "the username field"
        )
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = require(
            app.secureTextFields[A11yID.Login.password],
            "the password field"
        )
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons[A11yID.Login.submit].tap()

        require(
            app.buttons[A11yID.Tab.catalog],
            "the Catalog tab after logging in"
        )

        dismissSavePasswordSheetIfPresent()
    }

    /// Best-effort dismissal of the system "Save Password?" sheet.
    ///
    /// **The app now prevents this sheet from appearing at all** under `--uitesting`
    /// (`UITestEnvironment.shouldDisablePasswordAutofill`), because it proved impossible
    /// to dismiss reliably from the test process — tapping "Not Now" synthesizes an event
    /// but the sheet stays up, and it blocks every element beneath it.
    ///
    /// Kept as a safety net for the case where the suppression regresses: it detects the
    /// sheet and asserts, so the failure names the real cause instead of surfacing as an
    /// inexplicable "exists but not hittable" somewhere unrelated.
    ///
    /// Historical detail preserved below.
    ///
    /// ---
    ///
    /// Dismisses the system "Save Password?" sheet if iOS presents it.
    ///
    /// **This was the cause of the long-standing "cells exist but are not hittable"
    /// failure** (docs/plans/ios-ui-testing-plan.md §6b). `LoginView` uses
    /// `.textContentType(.password)` — correct for shipping, since it enables password
    /// autofill — so iOS offers to save the credential after a successful login. The
    /// sheet renders in a separate window above the app and makes **every** element
    /// report `isHittable == false`: not just book cells but the nav bar, the tab bar,
    /// even the tab buttons.
    ///
    /// It appears asynchronously and not on every launch, which is why the symptom
    /// looked intermittent. Poll for it rather than waiting a fixed interval.
    ///
    /// Test-only concern: a real user simply taps "Not Now".
    ///
    /// Deliberately does **not** gate on `isHittable`. `isHittable` is unreliable in this
    /// app — elements that tap successfully report `false` — so gating the "Not Now" tap
    /// on it made this helper give up silently while the sheet was still up, leaving
    /// every later query blocked. Detect the sheet by its own existence instead, and tap
    /// via `coordinate` so an inaccurate hittability result cannot veto the tap.
    /// `timeout` is short: with suppression working the sheet never appears, so this is
    /// pure overhead on every login. Long enough to catch a regression, not to stall.
    func dismissSavePasswordSheetIfPresent(timeout: TimeInterval = 2) {
        let sheet = app.descendants(matching: .sheet)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Save Password"))
            .firstMatch

        guard sheet.waitForExistence(timeout: timeout) else { return } // never appeared

        for label in ["Not Now", "Not now"] {
            let button = app.buttons[label]
            guard button.exists else { continue }
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            break
        }

        // The sheet blocks everything beneath it, so a silent failure here would surface
        // later as a baffling "exists but not hittable" on an unrelated element — which
        // is exactly the bug this helper was written to fix. Fail here instead.
        XCTAssertTrue(
            waitForNonExistence(sheet, timeout: 5),
            """
            The system "Save Password?" sheet is still presented. It renders in a separate \
            window above the app and blocks interaction with every element beneath it, so \
            the rest of this test would fail for the wrong reason.
            """
        )
    }

    /// Waits for an element to go away. `waitForExistence` has no negative form.
    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !element.exists
    }

    /// Looks up an element by identifier without caring about its element type.
    ///
    /// SwiftUI decides the type: `.accessibilityIdentifier` on a `ScrollView` root
    /// surfaces as `scrollViews`, on a `VStack` as `otherElements`. Querying
    /// `app.otherElements[…]` therefore silently misses elements that do exist, so
    /// match on the identifier alone.
    func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    /// Any book grid cell, matched on the identifier prefix.
    ///
    /// Cell identifiers embed the book's UUID, which is assigned by the database —
    /// `scripts/seed-e2e.ts` upserts on `asin`, so the id is stable per database but
    /// not knowable in advance and not portable to a fresh one. These flows only
    /// need *a* book, so match the prefix rather than hardcoding an id.
    ///
    /// Catalog and Library both render `BookGridItem`, so this works on either.
    var anyBookCell: XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", A11yID.bookCellPrefix))
            .firstMatch
    }

    /// Skips the test when the catalog never populates.
    ///
    /// These flows need `npm run dev` plus `npm run e2e:seed`. Skipping beats failing:
    /// a missing backend is an environment problem, and a red suite for that reason
    /// trains people to ignore it.
    func requireSeededCatalog() throws {
        guard anyBookCell.waitForExistence(timeout: UITestCase.defaultTimeout) else {
            throw XCTSkip(
                """
                No catalog books found. These flows need a running backend with seeded data:
                  npm run dev && npm run e2e:seed
                """
            )
        }
    }
}
