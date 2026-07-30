//
//  LoginFlowUITests.swift
//  BookVaultUITests
//
//  U1 from docs/plans/ios-ui-testing-plan.md.
//

import XCTest

/// U1 — the app launches to a usable login screen.
///
/// Deliberately requires no backend: this is the flow that proves the harness works
/// (launch, `--uitesting` reset, identifier lookup) before any test depends on
/// seeded data. It also covers the screen whose navigation container was removed in
/// A5 (#135), which had no automated verification at the time.
final class LoginFlowUITests: UITestCase {
    func testLoginScreenRendersItsControls() {
        require(app.textFields[A11yID.Login.username], "the username field")
        require(app.secureTextFields[A11yID.Login.password], "the password field")
        require(app.buttons[A11yID.Login.submit], "the Log In button")
    }

    func testSubmitIsDisabledUntilCredentialsAreEntered() {
        let submit = require(app.buttons[A11yID.Login.submit], "the Log In button")
        XCTAssertFalse(submit.isEnabled, "Log In should be disabled with empty fields")

        let username = app.textFields[A11yID.Login.username]
        username.tap()
        username.typeText("someone")

        let password = app.secureTextFields[A11yID.Login.password]
        password.tap()
        password.typeText("secret")

        XCTAssertTrue(submit.isEnabled, "Log In should enable once both fields are filled")
    }

    /// The `--uitesting` reset must land the app on the login screen even if a prior
    /// run left a session in the keychain. Guards the reset itself, not the UI.
    func testLaunchesUnauthenticated() {
        require(app.buttons[A11yID.Login.submit], "the login screen")
        XCTAssertFalse(
            app.buttons[A11yID.Tab.catalog].exists,
            "Expected no tab bar: the UI-testing launch argument should clear any stored session"
        )
    }
}
