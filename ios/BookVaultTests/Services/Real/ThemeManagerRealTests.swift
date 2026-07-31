//
//  ThemeManagerRealTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 1: Real Services Testing - ThemeManager
//

import SwiftUI
import XCTest
@testable import BookVault

// ThemeManager is @MainActor-isolated, so the tests must be too.
@MainActor
final class ThemeManagerRealTests: XCTestCase {
    // MARK: - Properties

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var themeManager: ThemeManager!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Create a unique suite name for each test to ensure isolation
        suiteName = "ThemeManagerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        // Clear any existing values
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        // Clean up the test defaults
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        themeManager = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithNoSavedTheme_DefaultsToSystem() {
        // Given: No saved theme in UserDefaults
        // When: Creating a new ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // Then: Default theme is system
        XCTAssertEqual(themeManager.selectedTheme, .system)
    }

    func testInitializationWithSavedLightTheme_LoadsLight() {
        // Given: Light theme saved in UserDefaults
        testDefaults.set(AppTheme.light.rawValue, forKey: ThemeManager.themeKey)

        // When: Creating a new ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // Then: Theme is loaded as light
        XCTAssertEqual(themeManager.selectedTheme, .light)
    }

    func testInitializationWithSavedDarkTheme_LoadsDark() {
        // Given: Dark theme saved in UserDefaults
        testDefaults.set(AppTheme.dark.rawValue, forKey: ThemeManager.themeKey)

        // When: Creating a new ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // Then: Theme is loaded as dark
        XCTAssertEqual(themeManager.selectedTheme, .dark)
    }

    func testInitializationWithSavedSystemTheme_LoadsSystem() {
        // Given: System theme saved in UserDefaults
        testDefaults.set(AppTheme.system.rawValue, forKey: ThemeManager.themeKey)

        // When: Creating a new ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // Then: Theme is loaded as system
        XCTAssertEqual(themeManager.selectedTheme, .system)
    }

    func testInitializationWithInvalidSavedValue_DefaultsToSystem() {
        // Given: Invalid theme value saved in UserDefaults
        testDefaults.set("InvalidTheme", forKey: ThemeManager.themeKey)

        // When: Creating a new ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // Then: Theme defaults to system
        XCTAssertEqual(themeManager.selectedTheme, .system)
    }

    func testInitializationWithEmptyString_DefaultsToSystem() {
        // Given: Empty string saved in UserDefaults
        testDefaults.set("", forKey: ThemeManager.themeKey)

        // When: Creating a new ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // Then: Theme defaults to system
        XCTAssertEqual(themeManager.selectedTheme, .system)
    }

    // MARK: - Theme Persistence Tests

    func testSettingTheme_PersistsToUserDefaults() {
        // Given: A ThemeManager with default settings
        themeManager = ThemeManager(userDefaults: testDefaults)

        // When: Setting theme to dark
        themeManager.selectedTheme = .dark

        // Then: Value is persisted to UserDefaults
        let savedValue = testDefaults.string(forKey: ThemeManager.themeKey)
        XCTAssertEqual(savedValue, AppTheme.dark.rawValue)
    }

    func testSettingThemeMultipleTimes_PersistsLastValue() {
        // Given: A ThemeManager
        themeManager = ThemeManager(userDefaults: testDefaults)

        // When: Setting theme multiple times
        themeManager.selectedTheme = .light
        themeManager.selectedTheme = .dark
        themeManager.selectedTheme = .system

        // Then: Last value is persisted
        let savedValue = testDefaults.string(forKey: ThemeManager.themeKey)
        XCTAssertEqual(savedValue, AppTheme.system.rawValue)
    }

    func testThemePersistence_SurvivesReinitialization() {
        // Given: A ThemeManager with dark theme set
        themeManager = ThemeManager(userDefaults: testDefaults)
        themeManager.selectedTheme = .dark

        // When: Creating a new ThemeManager with same UserDefaults
        let newThemeManager = ThemeManager(userDefaults: testDefaults)

        // Then: New instance has the persisted theme
        XCTAssertEqual(newThemeManager.selectedTheme, .dark)
    }

    // MARK: - AppTheme Enum Tests

    func testAppThemeRawValues() {
        XCTAssertEqual(AppTheme.system.rawValue, "System")
        XCTAssertEqual(AppTheme.light.rawValue, "Light")
        XCTAssertEqual(AppTheme.dark.rawValue, "Dark")
    }

    func testAppThemeCaseIterable() {
        // Verify all cases are included
        XCTAssertEqual(AppTheme.allCases.count, 3)
        XCTAssertTrue(AppTheme.allCases.contains(.system))
        XCTAssertTrue(AppTheme.allCases.contains(.light))
        XCTAssertTrue(AppTheme.allCases.contains(.dark))
    }

    func testAppThemeColorScheme_System() {
        XCTAssertNil(AppTheme.system.colorScheme)
    }

    func testAppThemeColorScheme_Light() {
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
    }

    func testAppThemeColorScheme_Dark() {
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    // MARK: - Theme Key Tests

    func testThemeKeyConstant() {
        XCTAssertEqual(ThemeManager.themeKey, "selectedTheme")
    }

    // MARK: - Isolation Tests

    func testDifferentUserDefaults_AreIsolated() {
        // Given: Two ThemeManagers with different UserDefaults
        let suite1 = "IsolationTest-1-\(UUID().uuidString)"
        let suite2 = "IsolationTest-2-\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suite1)!
        let defaults2 = UserDefaults(suiteName: suite2)!

        defer {
            defaults1.removePersistentDomain(forName: suite1)
            defaults2.removePersistentDomain(forName: suite2)
        }

        let manager1 = ThemeManager(userDefaults: defaults1)
        let manager2 = ThemeManager(userDefaults: defaults2)

        // When: Setting different themes
        manager1.selectedTheme = .dark
        manager2.selectedTheme = .light

        // Then: Each manager has its own theme
        XCTAssertEqual(manager1.selectedTheme, .dark)
        XCTAssertEqual(manager2.selectedTheme, .light)

        // And: UserDefaults are isolated
        XCTAssertEqual(defaults1.string(forKey: ThemeManager.themeKey), "Dark")
        XCTAssertEqual(defaults2.string(forKey: ThemeManager.themeKey), "Light")
    }
}
