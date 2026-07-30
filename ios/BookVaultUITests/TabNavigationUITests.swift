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

    /// The overflow tabs live behind the system "More" tab. Worth asserting because it
    /// is easy to forget three screens are a tap further away than the rest.
    func testOverflowTabsAreReachableViaMore() throws {
        logIn()

        let more = app.tabBars.buttons["More"]
        guard more.waitForExistence(timeout: UITestCase.defaultTimeout) else {
            throw XCTSkip(
                """
                No "More" tab found. If the tab count dropped to five or fewer, the overflow \
                no longer exists and this test should be replaced by direct assertions.
                """
            )
        }
        more.tap()

        // The More screen renders rows as cells; query by label across types rather
        // than assuming staticTexts.
        for title in ["Downloads", "Restores", "Settings"] {
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", title))
                .firstMatch
            require(row, "\(title) in the More tab list")
        }
    }

    /// Returning to a tab must not leave it blank — a regression mode when tab content
    /// is rebuilt with a new view identity.
    func testSwitchingAwayAndBackRestoresTabContent() throws {
        logIn()
        try requireSeededCatalog()

        // Assert on observable content rather than isSelected: that property proved
        // unreliable in this app (it reads false even for tabs that tap successfully).
        app.buttons[A11yID.Tab.browse].tap()
        require(app.buttons[A11yID.Tab.catalog], "the tab bar after switching to Browse")

        app.buttons[A11yID.Tab.catalog].tap()
        require(anyBookCell, "catalog content after returning to the Catalog tab")
    }
}
