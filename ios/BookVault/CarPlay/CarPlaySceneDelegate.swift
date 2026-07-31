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
/// This is deliberately a **walking skeleton**: it proves the scene connects and
/// can present a template, and nothing more. Real browse/playback templates come
/// in Track B, built on top of a `CarPlayCoordinator` that this delegate will
/// hold rather than putting logic here — a scene delegate cannot be unit-tested
/// without a head unit, so behavior belongs in testable objects instead.
///
/// `@MainActor` because `CPInterfaceController` and every template type are UI
/// objects. `UISceneDelegate` is not itself annotated, so the two protocol
/// methods below are `nonisolated` and hop explicitly — the same shape as
/// `AppDelegate`'s `UNUserNotificationCenterDelegate` conformance.
@MainActor
final class CarPlaySceneDelegate: UIResponder {
    /// Retained for the life of the connection; templates are pushed onto it.
    private var interfaceController: CPInterfaceController?
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
            self.presentSkeletonTemplate(on: controller.value)
        }
    }

    nonisolated func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didDisconnectInterfaceController _: CPInterfaceController
    ) {
        Task { @MainActor in
            // Drop the reference so a reconnect rebuilds cleanly rather than
            // pushing onto a dead controller.
            self.interfaceController = nil
            DebugLogger.info("CarPlay: interface controller disconnected")
        }
    }

    /// Placeholder root template.
    ///
    /// Exists only to prove the scene is live in the CarPlay Simulator. Track B
    /// replaces this with the real `CPTabBarTemplate` (Library / Series /
    /// Downloaded / Continue).
    private func presentSkeletonTemplate(on controller: CPInterfaceController) {
        let item = CPListItem(text: "Book Vault", detailText: "CarPlay scene connected")
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Book Vault", sections: [section])

        controller.setRootTemplate(template, animated: false, completion: nil)
    }
}
