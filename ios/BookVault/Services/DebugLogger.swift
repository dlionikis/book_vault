//
//  DebugLogger.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import Foundation
import OSLog

// MARK: - DebugLogger

/// Centralized debug logging utility that automatically respects DEBUG/RELEASE builds
/// Eliminates the need to scatter `#if DEBUG` throughout the codebase
///
/// Usage:
/// ```swift
/// // Simple logging
/// DebugLogger.log("User logged in")
///
/// // Categorized logging with emojis
/// DebugLogger.network("API request to /api/books")
/// DebugLogger.auth("Token refreshed successfully")
/// DebugLogger.error("Failed to decode response", error: decodingError)
///
/// // Conditional logging (only in debug builds)
/// DebugLogger.verbose("Detailed debug info: \(largeObject)")
/// ```
class DebugLogger {
    // MARK: - Configuration

    /// Global enable/disable flag - automatically set based on build configuration
    private static let isEnabled: Bool = {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }()

    /// Enable verbose logging for detailed debugging (can be toggled at runtime in debug builds)
    ///
    /// Backed by a lock rather than a plain `static var` because DebugLogger is called
    /// from every actor in the app; a nonisolated mutable global is rejected under the
    /// Swift 6 language mode. Same NSLock + @unchecked Sendable approach as
    /// `FileExtensionStorage` in DownloadManager.
    static var verboseLoggingEnabled: Bool {
        get { verboseFlag.value }
        set { verboseFlag.value = newValue }
    }

    private static let verboseFlag = AtomicBool(true)

    /// Minimal lock-protected `Bool` for cross-actor access.
    private final class AtomicBool: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Bool

        init(_ initial: Bool) { storage = initial }

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storage = newValue
            }
        }
    }

    // MARK: - Log Categories

    /// Categories for organizing log messages with visual indicators
    enum Category: String {
        case network = "🌐"
        case auth = "🔐"
        case audio = "🎵"
        case database = "💾"
        case ui = "🖼️"
        case error = "❌"
        case warning = "⚠️"
        case success = "✅"
        case info = "ℹ️"
        case debug = "🐛"
        case performance = "⚡️"
    }

    // MARK: - Logging Methods

    /// General purpose logging
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: Optional category for organizing logs (default: .debug)
    ///   - file: Source file (automatically captured)
    ///   - function: Source function (automatically captured)
    ///   - line: Source line (automatically captured)
    static func log(
        _ message: String,
        category: Category = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }

        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())

        print("\(timestamp) \(category.rawValue) [\(fileName):\(line)] \(function) - \(message)")
    }

    /// Network-related logging (API requests, responses, etc.)
    static func network(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .network, file: file, function: function, line: line)
    }

    /// Authentication-related logging (login, logout, token refresh, etc.)
    static func auth(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .auth, file: file, function: function, line: line)
    }

    /// Audio playback logging (player state, buffering, etc.)
    static func audio(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .audio, file: file, function: function, line: line)
    }

    /// Database/storage logging (Prisma queries, cache operations, etc.)
    static func database(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .database, file: file, function: function, line: line)
    }

    /// UI-related logging (view lifecycle, navigation, etc.)
    static func ui(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .ui, file: file, function: function, line: line)
    }

    /// Error logging with optional error object
    static func error(
        _ message: String,
        error: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var fullMessage = message
        if let error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(fullMessage, category: .error, file: file, function: function, line: line)
    }

    /// Warning logging for potential issues
    static func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .warning, file: file, function: function, line: line)
    }

    /// Success logging for completed operations
    static func success(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .success, file: file, function: function, line: line)
    }

    /// Info logging for general information
    static func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .info, file: file, function: function, line: line)
    }

    /// Performance/timing logging
    static func performance(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: .performance, file: file, function: function, line: line)
    }

    /// Verbose logging - only prints if verboseLoggingEnabled is true
    /// Useful for detailed debugging that would be too noisy normally
    static func verbose(
        _ message: String,
        category: Category = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled, verboseLoggingEnabled else { return }
        log(message, category: category, file: file, function: function, line: line)
    }

    // MARK: - Specialized Logging

    /// Log an API request with details
    static func apiRequest(
        method: String,
        path: String,
        body: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var message = "API Request: \(method) \(path)"
        if let body {
            message += " | Body: \(body)"
        }
        network(message, file: file, function: function, line: line)
    }

    /// Log an API response with status code
    /// - Note: The body parameter uses @autoclosure to defer evaluation until logging is actually needed.
    ///         This means expensive body formatting (like JSON truncation) is skipped entirely in release builds.
    static func apiResponse(
        path: String,
        statusCode: Int,
        body: @autoclosure () -> String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }

        var message = "API Response: \(path) | Status: \(statusCode)"
        if let bodyValue = body() {
            message += " | Body: \(bodyValue)"
        }

        // Use different categories based on status code
        let category: Category = switch statusCode {
        case 200 ... 299:
            .success
        case 400 ... 499:
            .warning
        case 500 ... 599:
            .error
        default:
            .network
        }

        log(message, category: category, file: file, function: function, line: line)
    }

    /// Measure and log execution time of a block
    /// - Parameters:
    ///   - label: Description of the operation being timed
    ///   - block: The block to execute and measure
    /// - Returns: Result of the block execution
    static func measure<T>(
        _ label: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try block() }

        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000 // Convert to milliseconds

        performance(
            "\(label) completed in \(String(format: "%.2f", elapsed))ms",
            file: file,
            function: function,
            line: line
        )

        return result
    }

    /// Async version of measure
    static func measure<T>(
        _ label: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else { return try await block() }

        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000 // Convert to milliseconds

        performance(
            "\(label) completed in \(String(format: "%.2f", elapsed))ms",
            file: file,
            function: function,
            line: line
        )

        return result
    }

    /// Log an object's description (only in debug builds)
    static func dump(
        _ object: some Any,
        label: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }

        let message = label ?? "Object dump"
        log("\(message):", category: .debug, file: file, function: function, line: line)
        Swift.dump(object)
    }

    // MARK: - Conditional Compilation Helpers

    /// Execute a block only in debug builds (useful for debug-only setup code)
    /// - Parameter block: Code to execute only in debug builds
    static func debugOnly(_ block: () -> Void) {
        #if DEBUG
            block()
        #endif
    }

    /// Execute a block only in debug builds (async version)
    static func debugOnly(_ block: () async -> Void) async {
        #if DEBUG
            await block()
        #endif
    }

    // MARK: - Helpers

    /// Date formatter for timestamps
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - OSLog Integration (iOS 14+)

/// Extended functionality using OSLog for better integration with Xcode Console and Instruments
extension DebugLogger {
    /// Log levels for OSLog integration
    enum LogLevel {
        case debug
        case info
        case warning
        case error

        @available(iOS 14.0, *)
        var osLogType: OSLogType {
            switch self {
            case .debug: .debug
            case .info: .info
            case .warning: .default
            case .error: .error
            }
        }
    }

    /// OSLog subsystem identifier
    private static let subsystem = "com.bookvault.BookVault"

    /// Log using OSLog (available iOS 14+)
    /// Provides better integration with Xcode Console filtering and Instruments
    @available(iOS 14.0, *)
    static func osLog(
        _ message: String,
        level: LogLevel = .debug,
        category: String = "general"
    ) {
        guard isEnabled else { return }

        let logger = Logger(subsystem: subsystem, category: category)

        switch level {
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }
    }
}
