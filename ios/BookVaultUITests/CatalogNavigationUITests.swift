//
//  CatalogNavigationUITests.swift
//  BookVaultUITests
//
//  U2 and U3 from docs/plans/ios-ui-testing-plan.md.
//

import XCTest

/// U2 — the catalog loads after login.
/// U3 — tapping a book pushes its detail screen, and back returns to the catalog.
///
/// **U3 closes the A5 gap.** A5 (#135) migrated every `NavigationView` to
/// `NavigationStack` and shipped with a fully green gate that could not verify
/// push/pop at all. This is that verification.
///
/// Requires a running backend with seeded data: `npm run dev && npm run e2e:seed`.
final class CatalogNavigationUITests: UITestCase {
    // MARK: - U2

    func testCatalogLoadsAfterLogin() throws {
        logIn()
        try requireSeededCatalog()

        XCTAssertTrue(
            anyBookCell.exists,
            "Expected at least one book cell in the catalog"
        )
    }

    // MARK: - U3

    func testTappingBookPushesDetailAndBackReturns() throws {
        logIn()
        try requireSeededCatalog()

        anyBookCell.tap()

        require(
            element(withIdentifier: A11yID.BookDetail.root),
            "the book detail screen after tapping a catalog cell"
        )

        // The back button is the first nav-bar button in a pushed NavigationStack.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        require(backButton, "a back button on the pushed detail screen")
        backButton.tap()

        require(anyBookCell, "the catalog again after tapping back")
        XCTAssertFalse(
            element(withIdentifier: A11yID.BookDetail.root).exists,
            "Expected the detail screen to be popped after tapping back"
        )
    }

    /// Push → pop → push again. A stack that pops incorrectly can still pass a
    /// single round trip, so exercise it twice.
    func testDetailCanBePushedAgainAfterPopping() throws {
        logIn()
        try requireSeededCatalog()

        for attempt in 1 ... 2 {
            anyBookCell.tap()
            require(
                element(withIdentifier: A11yID.BookDetail.root),
                "the detail screen on push \(attempt)"
            )
            app.navigationBars.buttons.element(boundBy: 0).tap()
            require(anyBookCell, "the catalog after pop \(attempt)")
        }
    }
}
