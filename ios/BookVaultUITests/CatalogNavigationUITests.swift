//
//  CatalogNavigationUITests.swift
//  BookVaultUITests
//
//  U2 from docs/plans/ios-ui-testing-plan.md.
//

import XCTest

/// U2 — the catalog loads after login.
///
/// **U3 (push → detail → back) is deliberately absent.** It is written but does not
/// pass: every book cell reports `hittable == false` even though it exists at a valid
/// on-screen frame, so the tap never lands. See the "Deferred" section of
/// docs/plans/ios-ui-testing-plan.md — U3 is the flow that closes the A5 gap, so it
/// is the highest-value thing left to fix here.
///
/// Requires a running backend with seeded data: `npm run dev && npm run e2e:seed`.
final class CatalogNavigationUITests: UITestCase {
    func testCatalogLoadsAfterLogin() throws {
        logIn()
        try requireSeededCatalog()

        XCTAssertTrue(
            anyBookCell.exists,
            "Expected at least one book cell in the catalog"
        )
    }
}
