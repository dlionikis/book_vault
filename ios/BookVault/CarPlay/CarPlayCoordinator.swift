//
//  CarPlayCoordinator.swift
//  BookVault
//
//  CarPlay tasks B3–B6 — template assembly and selection handling.
//

import CarPlay
import Combine
import UIKit

/// Owns the CarPlay template stack.
///
/// Split out of `CarPlaySceneDelegate` so the interesting parts — which tabs
/// exist, what a row does when tapped, what happens on logout — are reachable
/// from tests. The delegate keeps only scene lifecycle.
@MainActor
final class CarPlayCoordinator {
    private let provider: CarPlayLibraryProvider
    private let imageProvider: CarPlayImageProvider
    private let authManager: any AuthManaging
    private let onPlay: (Book) -> Void

    /// Configures the Now Playing template. Injected so tests can observe it
    /// without touching the shared CarPlay singleton.
    private let configureNowPlaying: () -> Void

    /// Fires when auth state may have changed.
    ///
    /// Injected as a plain publisher rather than read off `authManager`: an
    /// existential `any AuthManaging` cannot promise a concrete
    /// `ObjectWillChangePublisher`, and constraining the protocol would ripple
    /// through every conformer. This also lets tests drive auth transitions
    /// directly, which is the behavior C1 is really about.
    private let onAuthChange: AnyPublisher<Void, Never>

    private weak var interfaceController: CPInterfaceController?
    private var authObservation: AnyCancellable?

    /// What the root of the CarPlay stack should be.
    enum RootTemplateKind: Equatable {
        /// Session restore in flight — neutral, NOT the sign-in message.
        case loading
        case signIn
        case browse
    }

    /// CarPlay caps root tabs at 5; we ship 3 and have headroom.
    private enum Tab {
        static let library = "Library"
        static let series = "Series"
        static let downloaded = "Downloaded"
    }

    init(
        provider: CarPlayLibraryProvider,
        imageProvider: CarPlayImageProvider,
        authManager: any AuthManaging = AuthManager.shared,
        onAuthChange: AnyPublisher<Void, Never> = AuthManager.shared.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher(),
        onPlay: @escaping (Book) -> Void = { AudioPlayerManager.shared.play(book: $0) },
        configureNowPlaying: @escaping () -> Void = { CarPlayNowPlaying.configure() }
    ) {
        self.configureNowPlaying = configureNowPlaying
        self.provider = provider
        self.imageProvider = imageProvider
        self.authManager = authManager
        self.onAuthChange = onAuthChange
        self.onPlay = onPlay
    }

    // MARK: - Lifecycle

    func attach(to controller: CPInterfaceController) {
        interfaceController = controller

        // Swap the root template whenever auth state changes, so a logout on the
        // phone mid-drive replaces the browse UI with the sign-in message rather
        // than leaving stale, unplayable rows on screen. This also covers the
        // cold-start case: CarPlay can connect while `isRestoringSession` is
        // still true, and this fires again when the restore resolves.
        //
        // Observing `objectWillChange` rather than a concrete `@Published`
        // keeps this working against `AuthManaging` mocks. It fires *before* the
        // value changes, hence the hop to the next runloop turn.
        authObservation = onAuthChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.refreshRootTemplate() }
            }

        Task { await refreshRootTemplate() }
    }

    func detach() {
        authObservation = nil
        interfaceController = nil
    }

    // MARK: - Root template

    /// Choose and install the root template for the current auth state.
    ///
    /// The three-way split matters. `isRestoringSession` starts `true` while the
    /// keychain session is read, and CarPlay can connect before that finishes —
    /// treating "not authenticated yet" as "logged out" would flash a spurious
    /// sign-in screen on every cold start.
    func refreshRootTemplate() async {
        guard let controller = interfaceController else { return }

        switch await rootTemplateForCurrentState() {
        case .loading:
            controller.setRootTemplate(Self.loadingTemplate(), animated: false, completion: nil)
        case .signIn:
            controller.setRootTemplate(Self.signInTemplate(), animated: false, completion: nil)
        case .browse:
            let tabBar = CPTabBarTemplate(templates: [
                makeTemplate(title: Tab.library, load: provider.libraryRows),
                makeTemplate(title: Tab.series, load: { await self.provider.seriesRows() }),
                makeTemplate(title: Tab.downloaded, load: provider.downloadedRows)
            ])
            controller.setRootTemplate(tabBar, animated: false, completion: nil)
        }
    }

    /// Which root template the current auth state calls for.
    ///
    /// Split from `refreshRootTemplate()` so the decision is assertable without
    /// a `CPInterfaceController`: comparing `CPTemplate` objects in tests is
    /// brittle, and the interesting behavior is the choice, not the object.
    func rootTemplateForCurrentState() async -> RootTemplateKind {
        // `isRestoringSession` first, and deliberately so. It starts `true`
        // while the keychain session is read, and CarPlay can connect before
        // that finishes — checking `isAuthenticated` first would render a
        // spurious sign-in screen on every cold start.
        if authManager.isRestoringSession { return .loading }
        return authManager.isAuthenticated ? .browse : .signIn
    }

    // MARK: - Templates

    /// A list template that fills itself in asynchronously.
    ///
    /// CarPlay wants a template synchronously, but every data source here is
    /// async, so the template ships empty and is updated when the load lands.
    private func makeTemplate(
        title: String,
        load: @escaping () async -> CarPlayListState
    ) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = [title]
        template.emptyViewSubtitleVariants = ["Loading…"]

        Task {
            let state = await load()
            apply(state, to: template)
        }
        return template
    }

    private func apply(_ state: CarPlayListState, to template: CPListTemplate) {
        switch state {
        case let .loaded(rows):
            template.updateSections([CPListSection(items: rows.map(makeItem))])
        case let .empty(message), let .failed(message):
            // Both render the same way — an explained empty state. The
            // distinction matters to callers and tests, not to the driver.
            template.emptyViewSubtitleVariants = [message]
            template.updateSections([])
        }
    }

    private func makeItem(for row: CarPlayRow) -> CPListItem {
        let item = CPListItem(text: row.title, detailText: row.detail)

        if let bookId = row.bookId {
            imageProvider.loadCover(bookId: bookId, url: row.coverURL) { image in
                item.setImage(image)
            }
        }

        item.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }
            switch row.kind {
            case let .book(book):
                onPlay(book)
                // Push the system Now Playing screen so the driver lands
                // somewhere useful. It binds to MPNowPlayingInfoCenter, which
                // AudioPlayerManager already populates — no new playback logic.
                configureNowPlaying()
                interfaceController?.pushTemplate(
                    CPNowPlayingTemplate.shared,
                    animated: true,
                    completion: nil
                )
                completion()

            case let .series(id, title):
                Task {
                    let state = await self.provider.booksInSeries(id: id)
                    let sub = CPListTemplate(title: title, sections: [])
                    self.apply(state, to: sub)
                    self.interfaceController?.pushTemplate(sub, animated: true, completion: nil)
                    completion()
                }
            }
        }
        return item
    }

    private static func signInTemplate() -> CPInformationTemplate {
        CPInformationTemplate(
            title: "Sign In Required",
            layout: .leading,
            items: [CPInformationItem(title: "Open Book Vault on your phone to sign in.", detail: nil)],
            actions: []
        )
    }

    private static func loadingTemplate() -> CPInformationTemplate {
        CPInformationTemplate(
            title: "Book Vault",
            layout: .leading,
            items: [CPInformationItem(title: "Loading your library…", detail: nil)],
            actions: []
        )
    }
}
