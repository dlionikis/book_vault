//
//  AppIconManager.swift
//  BookVault
//
//  Created by Claude Code on 2/8/26.
//

import SwiftUI

// MARK: - AppIconColor

enum AppIconColor: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case indigo = "Indigo"
    case purple = "Purple"
    case teal = "Teal"
    case green = "Green"
    case orange = "Orange"
    case red = "Red"
    case graphite = "Graphite"

    var id: String { rawValue }

    /// The alternate icon name registered in Info.plist, or nil for the primary (Blue)
    var alternateIconName: String? {
        switch self {
        case .blue: return nil
        default: return "AppIcon-\(rawValue)"
        }
    }

    /// SwiftUI color for the settings UI preview
    var displayColor: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .graphite: return Color(.systemGray)
        }
    }
}

// MARK: - AppIconManager

/// Manages alternate app icon selection and persistence
@MainActor
class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    // MARK: - Constants

    static let iconKey = "selectedAppIcon"

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private var pendingIconTask: Task<Void, Never>?

    @Published var selectedIcon: AppIconColor {
        didSet {
            guard selectedIcon != oldValue else { return }
            userDefaults.set(selectedIcon.rawValue, forKey: AppIconManager.iconKey)
            applyIcon(selectedIcon)
        }
    }

    // MARK: - Initialization

    /// Production singleton initializer using standard UserDefaults
    private convenience init() {
        self.init(userDefaults: .standard)
    }

    /// Testable initializer that accepts a UserDefaults instance
    /// - Parameter userDefaults: The UserDefaults store to use for persistence
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        let saved = userDefaults.string(forKey: AppIconManager.iconKey)
        self.selectedIcon = AppIconColor(rawValue: saved ?? "") ?? .blue
    }

    /// Whether the device supports alternate icons
    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    // MARK: - Private Methods

    private func applyIcon(_ icon: AppIconColor) {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        // Cancel any in-flight icon change to avoid concurrent calls
        pendingIconTask?.cancel()
        pendingIconTask = Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
            } catch {
                print("Failed to set alternate icon: \(error.localizedDescription)")
            }
        }
    }
}
