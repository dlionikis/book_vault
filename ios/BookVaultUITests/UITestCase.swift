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
    }
}
