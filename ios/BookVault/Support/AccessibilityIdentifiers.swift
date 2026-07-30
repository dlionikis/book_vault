//
//  AccessibilityIdentifiers.swift
//  BookVault
//
//  Stable accessibility identifiers for UI tests.
//

/// Accessibility identifiers used by the XCUITest suite.
///
/// These are deliberately separate from `.accessibilityLabel`, which is
/// user-facing text: labels are localized, reworded, and (for book titles) come
/// from live data, so querying them in tests couples the tests to copy. These
/// identifiers are invisible to users and change only when someone edits them.
///
/// Shared here rather than inlined as string literals so a rename is a compile
/// error in the tests instead of a silent query failure at runtime.
///
/// See docs/plans/ios-ui-testing-plan.md.
enum A11y {
    enum Login {
        static let username = "login.username"
        static let password = "login.password"
        static let submit = "login.submit"
        static let continueOffline = "login.continueOffline"
    }

    enum Tab {
        static let catalog = "tab.catalog"
        static let browse = "tab.browse"
        static let search = "tab.search"
        static let library = "tab.library"
        static let downloads = "tab.downloads"
        static let restores = "tab.restores"
        static let settings = "tab.settings"
        static let offline = "tab.offline"
    }

    enum Catalog {
        static let grid = "catalog.grid"

        /// Per-item identifier. Uses the book id so tests can target a seeded
        /// fixture without depending on its title.
        static func cell(_ bookId: String) -> String { "catalog.cell.\(bookId)" }
    }

    enum BookDetail {
        static let root = "bookDetail.root"
        static let play = "bookDetail.play"
    }

    enum MiniPlayer {
        static let root = "miniPlayer.root"
        static let playPause = "miniPlayer.playPause"
    }

    enum NowPlaying {
        static let root = "nowPlaying.root"
    }
}
