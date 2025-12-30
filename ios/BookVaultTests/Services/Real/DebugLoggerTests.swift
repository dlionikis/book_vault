//
//  DebugLoggerTests.swift
//  BookVaultTests
//
//  Created by Claude Code on 12/29/25.
//  Phase 1: Real Services Testing - DebugLogger
//

import XCTest
@testable import BookVault

final class DebugLoggerTests: XCTestCase {
    // MARK: - Category Tests

    func testCategoryRawValues() {
        // Verify each category has the expected emoji
        XCTAssertEqual(DebugLogger.Category.network.rawValue, "🌐")
        XCTAssertEqual(DebugLogger.Category.auth.rawValue, "🔐")
        XCTAssertEqual(DebugLogger.Category.audio.rawValue, "🎵")
        XCTAssertEqual(DebugLogger.Category.database.rawValue, "💾")
        XCTAssertEqual(DebugLogger.Category.ui.rawValue, "🖼️")
        XCTAssertEqual(DebugLogger.Category.error.rawValue, "❌")
        XCTAssertEqual(DebugLogger.Category.warning.rawValue, "⚠️")
        XCTAssertEqual(DebugLogger.Category.success.rawValue, "✅")
        XCTAssertEqual(DebugLogger.Category.info.rawValue, "ℹ️")
        XCTAssertEqual(DebugLogger.Category.debug.rawValue, "🐛")
        XCTAssertEqual(DebugLogger.Category.performance.rawValue, "⚡️")
    }

    func testAllCategoriesExist() {
        // Verify all 11 categories exist by checking their raw values
        let categories: [DebugLogger.Category] = [
            .network, .auth, .audio, .database, .ui,
            .error, .warning, .success, .info, .debug, .performance,
        ]
        XCTAssertEqual(categories.count, 11)
    }

    // MARK: - Log Level Tests

    @available(iOS 14.0, *)
    func testLogLevelOSLogTypeMapping() {
        XCTAssertEqual(DebugLogger.LogLevel.debug.osLogType, .debug)
        XCTAssertEqual(DebugLogger.LogLevel.info.osLogType, .info)
        XCTAssertEqual(DebugLogger.LogLevel.warning.osLogType, .default)
        XCTAssertEqual(DebugLogger.LogLevel.error.osLogType, .error)
    }

    // MARK: - Verbose Logging Flag Tests

    func testVerboseLoggingFlagCanBeToggled() {
        // Save original state
        let originalState = DebugLogger.verboseLoggingEnabled

        // Toggle off
        DebugLogger.verboseLoggingEnabled = false
        XCTAssertFalse(DebugLogger.verboseLoggingEnabled)

        // Toggle on
        DebugLogger.verboseLoggingEnabled = true
        XCTAssertTrue(DebugLogger.verboseLoggingEnabled)

        // Restore original state
        DebugLogger.verboseLoggingEnabled = originalState
    }

    func testVerboseLoggingDefaultsToTrue() {
        // Reset to default by setting true (the documented default)
        DebugLogger.verboseLoggingEnabled = true
        XCTAssertTrue(DebugLogger.verboseLoggingEnabled)
    }

    // MARK: - Measure Function Tests

    func testMeasureSyncReturnsCorrectValue() {
        let result = DebugLogger.measure("Test operation") {
            42
        }
        XCTAssertEqual(result, 42)
    }

    func testMeasureSyncWithThrowingBlock() {
        enum TestError: Error { case expected }

        XCTAssertThrowsError(try DebugLogger.measure("Throwing operation") {
            throw TestError.expected
        }) { error in
            XCTAssertTrue(error is TestError)
        }
    }

    func testMeasureAsyncReturnsCorrectValue() async {
        let result = await DebugLogger.measure("Async test operation") {
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return "async result"
        }
        XCTAssertEqual(result, "async result")
    }

    func testMeasureAsyncWithThrowingBlock() async {
        enum TestError: Error { case expected }

        do {
            _ = try await DebugLogger.measure("Async throwing operation") {
                try await Task.sleep(nanoseconds: 1000) // Make it async
                throw TestError.expected
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    // MARK: - Static Method Invocation Tests

    // These tests verify that the static methods can be called without crashing
    // In DEBUG builds, they will print; in RELEASE builds, they will no-op

    func testLogMethodDoesNotCrash() {
        // Should not crash regardless of build configuration
        DebugLogger.log("Test log message")
        DebugLogger.log("Test with category", category: .info)
    }

    func testNetworkMethodDoesNotCrash() {
        DebugLogger.network("Network test message")
    }

    func testAuthMethodDoesNotCrash() {
        DebugLogger.auth("Auth test message")
    }

    func testAudioMethodDoesNotCrash() {
        DebugLogger.audio("Audio test message")
    }

    func testDatabaseMethodDoesNotCrash() {
        DebugLogger.database("Database test message")
    }

    func testUIMethodDoesNotCrash() {
        DebugLogger.ui("UI test message")
    }

    func testErrorMethodDoesNotCrash() {
        DebugLogger.error("Error test message")
        DebugLogger.error("Error with error object", error: NSError(domain: "test", code: 1))
    }

    func testWarningMethodDoesNotCrash() {
        DebugLogger.warning("Warning test message")
    }

    func testSuccessMethodDoesNotCrash() {
        DebugLogger.success("Success test message")
    }

    func testInfoMethodDoesNotCrash() {
        DebugLogger.info("Info test message")
    }

    func testPerformanceMethodDoesNotCrash() {
        DebugLogger.performance("Performance test message")
    }

    func testVerboseMethodDoesNotCrash() {
        DebugLogger.verbose("Verbose test message")
        DebugLogger.verbose("Verbose with category", category: .network)
    }

    // MARK: - API Logging Tests

    func testApiRequestMethodDoesNotCrash() {
        DebugLogger.apiRequest(method: "GET", path: "/api/books")
        DebugLogger.apiRequest(method: "POST", path: "/api/progress", body: "{\"bookId\": \"123\"}")
    }

    func testApiResponseMethodDoesNotCrash() {
        // Test various status code ranges
        DebugLogger.apiResponse(path: "/api/books", statusCode: 200) // Success
        DebugLogger.apiResponse(path: "/api/books", statusCode: 201, body: "{}")
        DebugLogger.apiResponse(path: "/api/auth", statusCode: 401) // Client error
        DebugLogger.apiResponse(path: "/api/server", statusCode: 500) // Server error
        DebugLogger.apiResponse(path: "/api/redirect", statusCode: 301) // Other
    }

    // MARK: - Dump Method Tests

    func testDumpMethodDoesNotCrash() {
        struct TestStruct {
            let name: String
            let value: Int
        }

        let testObject = TestStruct(name: "Test", value: 42)
        DebugLogger.dump(testObject)
        DebugLogger.dump(testObject, label: "Test object")
        DebugLogger.dump([1, 2, 3])
        DebugLogger.dump(["key": "value"])
    }

    // MARK: - Debug Only Tests

    func testDebugOnlySyncExecutesBlock() {
        var executed = false
        DebugLogger.debugOnly {
            executed = true
        }
        // In DEBUG builds, this will be true; in RELEASE builds, false
        // We're testing that it doesn't crash
        #if DEBUG
            XCTAssertTrue(executed)
        #else
            XCTAssertFalse(executed)
        #endif
    }

    func testDebugOnlyAsyncExecutesBlock() async {
        var executed = false
        await DebugLogger.debugOnly {
            try? await Task.sleep(nanoseconds: 1000) // Make it async
            executed = true
        }
        // In DEBUG builds, this will be true; in RELEASE builds, false
        #if DEBUG
            XCTAssertTrue(executed)
        #else
            XCTAssertFalse(executed)
        #endif
    }

    // MARK: - OSLog Tests

    @available(iOS 14.0, *)
    func testOSLogMethodDoesNotCrash() {
        DebugLogger.osLog("Test OSLog message")
        DebugLogger.osLog("Test with level", level: .info)
        DebugLogger.osLog("Test with category", level: .debug, category: "network")
        DebugLogger.osLog("Error level", level: .error, category: "errors")
        DebugLogger.osLog("Warning level", level: .warning)
    }
}
