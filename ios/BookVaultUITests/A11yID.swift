//
//  A11yID.swift
//  BookVaultUITests
//
//  Accessibility identifiers, mirrored from the app target.
//

/// Mirror of `A11y` in the app target.
///
/// UI test bundles run out-of-process and cannot `@testable import` the app, so the
/// identifier strings have to be declared on both sides. The app's
/// `Support/AccessibilityIdentifiers.swift` is the source of truth — keep these in
/// sync with it. `A11yIdentifierParityTests` in the unit-test target guards the
/// literals used here against renames.
enum A11yID {
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

    /// Book grid cell, shared by Catalog and Library.
    static func bookCell(_ bookId: String) -> String { "bookCell.\(bookId)" }

    /// Prefix for predicate-based lookups (the id is DB-assigned, so tests match
    /// the prefix rather than a known id).
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
