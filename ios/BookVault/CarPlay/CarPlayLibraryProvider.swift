//
//  CarPlayLibraryProvider.swift
//  BookVault
//
//  CarPlay task B2 — data → row models.
//

import Foundation

// MARK: - CarPlayRow

/// One browsable row, independent of CarPlay's own types.
///
/// The provider deliberately returns these rather than `CPListItem`s. `CPListItem`
/// is a UIKit-ish object that is awkward to assert on, so keeping the mapping
/// logic in plain values is what makes this layer unit-testable without a head
/// unit — the point of splitting the provider out of the scene delegate at all.
struct CarPlayRow: Equatable {
    enum Kind: Equatable {
        /// Plays immediately when selected.
        case book(Book)
        /// Drills into the series' book list.
        case series(id: UUID, title: String)
    }

    let title: String
    let detail: String?
    let kind: Kind

    /// The cover to show, when there is one.
    var coverURL: URL? {
        switch kind {
        case let .book(book):
            book.coverUrl.flatMap(URL.init(string:))
        case .series:
            nil
        }
    }

    /// Book id, for cover-cache lookups. `nil` for series rows.
    var bookId: UUID? {
        switch kind {
        case let .book(book): book.id
        case .series: nil
        }
    }
}

// MARK: - CarPlayListState

/// What a template should render.
///
/// Empty and error are separate cases on purpose: CarPlay showing a blank list
/// with no explanation is the failure mode called out in the plan's manual
/// matrix ("never show an empty unexplained list").
enum CarPlayListState: Equatable {
    case loaded([CarPlayRow])
    /// Nothing to show, with a reason the driver can read at a glance.
    case empty(message: String)
    /// The fetch failed. `message` is already driver-appropriate — short, and
    /// never a raw error description.
    case failed(message: String)
}

// MARK: - CarPlayLibraryProvider

/// Turns app data into `CarPlayListState` for the CarPlay templates.
///
/// Takes protocols rather than singletons so it can be exercised against
/// `MockAPIClient` and friends, per the DI hardening invariant.
@MainActor
struct CarPlayLibraryProvider {
    private let libraryManager: any LibraryManaging
    private let apiClient: any APIClientProtocol
    private let storageManager: any StorageManaging
    private let networkMonitor: any NetworkMonitoring

    init(
        libraryManager: any LibraryManaging,
        apiClient: any APIClientProtocol,
        storageManager: any StorageManaging,
        networkMonitor: any NetworkMonitoring
    ) {
        self.libraryManager = libraryManager
        self.apiClient = apiClient
        self.storageManager = storageManager
        self.networkMonitor = networkMonitor
    }

    // MARK: - Library

    /// Every book in the user's library, newest addition first.
    func libraryRows() async -> CarPlayListState {
        do {
            let books = try await libraryManager.fetchLibraryBooks(forceRefresh: false)
            guard !books.isEmpty else {
                return .empty(message: "Your library is empty. Add books on your phone.")
            }
            let rows = books
                .sorted { $0.addedAt > $1.addedAt }
                .map { Self.row(for: $0.asBook) }
            return .loaded(rows)
        } catch {
            return .failed(message: message(for: error, offlineHint: "your library"))
        }
    }

    // MARK: - Series

    /// Series in the user's library. Standalone books in the feed are included
    /// as playable rows, matching the phone app's mixed Books/Series toggle.
    func seriesRows(page: Int = 1, limit: Int = 50) async -> CarPlayListState {
        do {
            let response = try await apiClient.fetchLibrarySeriesView(page: page, limit: limit)
            let rows: [CarPlayRow] = response.results.compactMap { item in
                // Exactly one of series/book is set per item (enforced
                // server-side, per the schema comment). Handle both anyway
                // rather than assuming.
                if let series = item.series {
                    let owned = series.ownedCount ?? series.bookCount
                    return CarPlayRow(
                        title: series.title,
                        detail: "\(owned) of \(series.bookCount) books",
                        kind: .series(id: series.id, title: series.title)
                    )
                }
                if let book = item.book {
                    return Self.row(for: book)
                }
                return nil
            }
            guard !rows.isEmpty else {
                return .empty(message: "No series in your library yet.")
            }
            return .loaded(rows)
        } catch {
            return .failed(message: message(for: error, offlineHint: "your series"))
        }
    }

    /// Books inside one series, filtered from the user's library.
    ///
    /// Deliberately derived from the already-fetched library rather than a
    /// per-series endpoint. `APIClientProtocol` has no `fetchSeries`, and adding
    /// one purely for CarPlay would widen a protocol every mock must implement.
    /// It is also the better behavior here: CarPlay can only *play* books, and
    /// the library is what the user owns, so a series' non-owned books would be
    /// unplayable rows. This works from the disk cache offline, too.
    func booksInSeries(id: UUID) async -> CarPlayListState {
        do {
            let books = try await libraryManager.fetchLibraryBooks(forceRefresh: false)
            let inSeries = books
                .filter { book in book.series?.contains { $0.id == id } ?? false }
                .sorted { lhs, rhs in
                    // Series order when the server provides a sequence, title
                    // otherwise. Books missing a sequence sort last rather than
                    // jumbling in among the numbered ones.
                    let lhsSeq = lhs.series?.first { $0.id == id }?.sequence
                    let rhsSeq = rhs.series?.first { $0.id == id }?.sequence
                    switch (lhsSeq, rhsSeq) {
                    case let (lv?, rv?): return lv == rv ? lhs.title < rhs.title : lv < rv
                    case (nil, _?): return false
                    case (_?, nil): return true
                    case (nil, nil): return lhs.title < rhs.title
                    }
                }
            guard !inSeries.isEmpty else {
                return .empty(message: "No books from this series in your library.")
            }
            return .loaded(inSeries.map { Self.row(for: $0.asBook) })
        } catch {
            return .failed(message: message(for: error, offlineHint: "this series"))
        }
    }

    // MARK: - Downloaded

    /// Books already on the device.
    ///
    /// The most valuable tab in a car: it is the only one guaranteed to work
    /// with no signal.
    func downloadedRows() async -> CarPlayListState {
        // Downloads are known locally, so this deliberately does not require the
        // network — and falls back to the disk-cached library when offline.
        let books: [LibraryBook]
        do {
            books = try await libraryManager.fetchLibraryBooks(forceRefresh: false)
        } catch {
            return .failed(message: "Couldn't load your downloads.")
        }

        let downloaded = books.filter { storageManager.isBookDownloaded(bookId: $0.id.uuidString) }
        guard !downloaded.isEmpty else {
            return .empty(message: "No downloaded books. Download on your phone to listen offline.")
        }
        return .loaded(downloaded.map { Self.row(for: $0.asBook) })
    }

    // MARK: - Helpers

    private static func row(for book: Book) -> CarPlayRow {
        CarPlayRow(
            title: book.title,
            detail: book.authors.first?.name,
            kind: .book(book)
        )
    }

    /// Driver-appropriate failure text.
    ///
    /// Never surfaces a raw `error.localizedDescription`: those are long, often
    /// contain URLs, and are unreadable at a glance while driving.
    private func message(for _: Error, offlineHint: String) -> String {
        networkMonitor.isConnected
            ? "Couldn't load \(offlineHint). Try again."
            : "You're offline. Downloaded books are still available."
    }
}
