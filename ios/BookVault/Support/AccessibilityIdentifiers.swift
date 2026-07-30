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

    /// A book grid cell. Shared by Catalog and Library, which render the same
    /// `BookGridItem`, so UI tests can find a book on either screen with one prefix.
    ///
    /// Keyed on the book id rather than the title: titles come from live data and
    /// change, ids do not. Tests match on the `bookCell.` prefix because the id is
    /// assigned by the database and is not knowable in advance.
    static func bookCell(_ bookId: String) -> String { "bookCell.\(bookId)" }

    /// Prefix for `bookCell(_:)`, for predicate-based lookups.
    static let bookCellPrefix = "bookCell."

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
