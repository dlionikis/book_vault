//
//  TabNavigationUITests.swift
//  BookVaultUITests
//
//  U4 from docs/plans/ios-ui-testing-plan.md.
//

import XCTest

/// U4 — the directly visible tabs are reachable and select correctly.
///
/// Two related tests are deferred: reaching the overflow tabs via "More", and
/// switching away and back. Both depend on interactions that currently fail for the
/// same reason as U3 (elements existing but not hittable). See the "Deferred" section
/// of docs/plans/ios-ui-testing-plan.md.
///
/// Requires a running backend: `npm run dev`.
final class TabNavigationUITests: UITestCase {
    /// Tabs iOS shows directly in the bar.
    ///
    /// `ContentView` declares **seven** online tabs, but a `TabView` with more than
    /// five collapses the overflow into a system "More" tab, so Downloads, Restores
    /// and Settings are not directly tappable — only the first four plus "More" are
    /// visible. The Offline tab is excluded too: it only appears without connectivity,
    /// which this suite cannot toggle.
    private var directlyVisibleTabs: [(id: String, title: String)] {
        [
            (A11yID.Tab.catalog, "Catalog"),
            (A11yID.Tab.browse, "Browse"),
            (A11yID.Tab.search, "Search"),
            (A11yID.Tab.library, "Library")
        ]
    }

    func testDirectlyVisibleTabsAreReachable() {
        logIn()

        for tab in directlyVisibleTabs {
            let button = require(app.buttons[tab.id], "the \(tab.title) tab button")
            button.tap()
            XCTAssertTrue(
                button.isSelected,
                "Expected the \(tab.title) tab to be selected after tapping it"
            )
        }
    }
}
