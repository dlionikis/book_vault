//
//  XCTestCase+Async.swift
//  BookVaultTests
//
//  Async testing utilities.
//

import XCTest

extension XCTestCase {
    /// Helper for testing async code on MainActor
    @MainActor
    func awaitPublisher<T: ObservableObject>(
        _ object: T,
        timeout: TimeInterval = 1.0,
        condition: @escaping (T) -> Bool
    ) async throws {
        let start = Date()
        while !condition(object) {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    /// Helper to wait for async operation with timeout
    func waitForAsync(
        timeout: TimeInterval = 2.0,
        description: String = "Async operation",
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let expectation = expectation(description: description)

        Task {
            do {
                try await operation()
                expectation.fulfill()
            } catch {
                XCTFail("Async operation failed: \(error)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: timeout)
    }
}
