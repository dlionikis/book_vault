//
//  ThemeManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//

import SwiftUI

// MARK: - AppTheme

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

// MARK: - ThemeManager

/// Manages app theme preferences
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    // MARK: - Constants

    static let themeKey = "selectedTheme"

    // MARK: - Properties

    private let userDefaults: UserDefaults

    @Published var selectedTheme: AppTheme {
        didSet {
            userDefaults.set(selectedTheme.rawValue, forKey: ThemeManager.themeKey)
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
        // Load saved theme or default to system
        let savedTheme = userDefaults.string(forKey: ThemeManager.themeKey)
        self.selectedTheme = AppTheme(rawValue: savedTheme ?? "") ?? .system
    }
}
