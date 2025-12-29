//
//  ThemeManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//

import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// Manages app theme preferences
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
        }
    }

    private init() {
        // Load saved theme or default to system
        let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme")
        self.selectedTheme = AppTheme(rawValue: savedTheme ?? "") ?? .system
    }
}
