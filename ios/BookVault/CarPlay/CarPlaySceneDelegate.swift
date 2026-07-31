//
//  CarPlaySceneDelegate.swift
//  BookVault
//
//  CarPlay scene entry point (CarPlay task A2 — walking skeleton).
//

import CarPlay
import UIKit

/// Owns the CarPlay scene lifecycle.
///
/// Deliberately thin: everything interesting lives in `CarPlayCoordinator`,
/// which is unit-testable. A scene delegate is not — it needs a head unit — so
/// this holds lifecycle only.
///
/// `@MainActor` because `CPInterfaceController` and every template type are UI
/// objects. `UISceneDelegate` is not itself annotated, so the two protocol
/// methods below are `nonisolated` and hop explicitly — the same shape as
/// `AppDelegate`'s `UNUserNotificationCenterDelegate` conformance.
@MainActor
final class CarPlaySceneDelegate: UIResponder {
    /// Retained for the life of the connection; templates are pushed onto it.
    private var interfaceController: CPInterfaceController?

    private lazy var coordinator = CarPlayCoordinator(
        provider: CarPlayLibraryProvider(
            libraryManager: LibraryManager.shared,
            apiClient: APIClient.shared,
            storageManager: StorageManager.shared,
            networkMonitor: NetworkMonitor.shared
        ),
        imageProvider: CarPlayImageProvider()
    )
}

// MARK: - CPTemplateApplicationSceneDelegate

extension CarPlaySceneDelegate: CPTemplateApplicationSceneDelegate {
    nonisolated func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        let controller = UncheckedBox(interfaceController)
        Task { @MainActor in
            self.interfaceController = controller.value
            DebugLogger.info("CarPlay: interface controller connected")
            self.coordinator.attach(to: controller.value)
        }
    }

    nonisolated func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didDisconnectInterfaceController _: CPInterfaceController
    ) {
        Task { @MainActor in
            // Drop the references so a reconnect rebuilds cleanly rather than
            // pushing onto a dead controller.
            self.coordinator.detach()
            self.interfaceController = nil
            DebugLogger.info("CarPlay: interface controller disconnected")
        }
    }
}
