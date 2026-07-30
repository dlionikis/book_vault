//
//  A11yIdentifierParityTests.swift
//  BookVaultTests
//
//  Guards the accessibility identifiers the UI test suite depends on.
//

@testable import BookVault
import XCTest

/// The UI test bundle cannot import the app target, so `BookVaultUITests/A11yID.swift`
/// duplicates these strings. Duplication drifts silently, so pin the app-side values
/// here: renaming one without the other fails this test rather than producing a UI
/// test that mysteriously cannot find an element.
final class A11yIdentifierParityTests: XCTestCase {
    func testLoginIdentifiers() {
        XCTAssertEqual(A11y.Login.username, "login.username")
        XCTAssertEqual(A11y.Login.password, "login.password")
        XCTAssertEqual(A11y.Login.submit, "login.submit")
        XCTAssertEqual(A11y.Login.continueOffline, "login.continueOffline")
    }

    func testTabIdentifiers() {
        XCTAssertEqual(A11y.Tab.catalog, "tab.catalog")
        XCTAssertEqual(A11y.Tab.browse, "tab.browse")
        XCTAssertEqual(A11y.Tab.search, "tab.search")
        XCTAssertEqual(A11y.Tab.library, "tab.library")
        XCTAssertEqual(A11y.Tab.downloads, "tab.downloads")
        XCTAssertEqual(A11y.Tab.restores, "tab.restores")
        XCTAssertEqual(A11y.Tab.settings, "tab.settings")
        XCTAssertEqual(A11y.Tab.offline, "tab.offline")
    }

    /// Shared by Catalog and Library. UI tests match on the prefix because the id is
    /// assigned by the database, so keep the prefix and the builder consistent.
    func testBookCellIdentifiers() {
        XCTAssertEqual(A11y.bookCellPrefix, "bookCell.")
        XCTAssertEqual(
            A11y.bookCell("11111111-1111-1111-1111-111111111111"),
            "bookCell.11111111-1111-1111-1111-111111111111"
        )
        XCTAssertTrue(
            A11y.bookCell("abc").hasPrefix(A11y.bookCellPrefix),
            "bookCell(_:) must start with bookCellPrefix or prefix-matching in UI tests breaks"
        )
    }

    func testDetailAndPlayerIdentifiers() {
        XCTAssertEqual(A11y.BookDetail.root, "bookDetail.root")
        XCTAssertEqual(A11y.BookDetail.play, "bookDetail.play")
        XCTAssertEqual(A11y.MiniPlayer.root, "miniPlayer.root")
        XCTAssertEqual(A11y.MiniPlayer.info, "miniPlayer.info")
        XCTAssertEqual(A11y.MiniPlayer.playPause, "miniPlayer.playPause")
        XCTAssertEqual(A11y.NowPlaying.root, "nowPlaying.root")
    }

    /// The launch-argument hooks must stay off in a normal run, or shipping builds
    /// would clear the keychain on every launch.
    func testUITestEnvironmentIsInactiveByDefault() {
        // Unit tests run without `--uitesting`.
        XCTAssertFalse(UITestEnvironment.isActive)
        XCTAssertFalse(UITestEnvironment.shouldResetSession)
        XCTAssertFalse(UITestEnvironment.shouldSkipInitialBookLoad)
        XCTAssertFalse(UITestEnvironment.shouldSkipPushAuthorization)
        // Must stay false in shipping builds or users lose password autofill.
        XCTAssertFalse(UITestEnvironment.shouldDisablePasswordAutofill)
    }
}
