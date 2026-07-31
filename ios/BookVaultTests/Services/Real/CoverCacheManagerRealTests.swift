//
//  CoverCacheManagerRealTests.swift
//  BookVaultTests
//
//  Tests the real CoverCacheManager against a mocked URLSession.
//
//  The security-critical behavior: the API bearer token is attached ONLY when
//  the download URL is on the API host (dev builds serve covers via the
//  authenticated /api/images route). It must NEVER be attached to presigned S3
//  URLs (production), or the token would leak to S3. Added alongside the #75
//  auth change, which shipped without an iOS-side test.
//
//  Reuses MockURLProtocol from APIClientRealTests.swift (same test target).
//

import XCTest
import UIKit

@testable import BookVault

@MainActor
/// `@unchecked Sendable` so test bodies can capture `self` inside the
/// `@Sendable` closures these tests hand to URLProtocol / refresh handlers.
/// XCTest drives one instance per test method and never concurrently, so
/// there is no cross-test sharing to race on.
final class CoverCacheManagerRealTests: XCTestCase, @unchecked Sendable {
    private var tempDir: URL!
    private var mockSession: URLSession!

    private let apiBaseURL = URL(string: "http://localhost:3000")!
    private let token = "test-bearer-token"

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempDir)
        mockSession = nil
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A 1x1 PNG so `UIImage(data:)` succeeds and `cacheCover` completes.
    ///
    /// `nonisolated` because the `@Sendable` URLProtocol handlers below call it.
    /// It touches no test state, so there is nothing to isolate.
    nonisolated private func pngData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.pngData()!
    }

    nonisolated private func okResponse(for url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "image/png"])!
    }

    /// Build a manager with the API-host token providers wired, using the mock session.
    private func makeManager(
        token: String? = nil,
        apiBaseURL: URL? = nil
    ) -> CoverCacheManager {
        CoverCacheManager(
            cacheDirectory: tempDir,
            userIdProvider: { "test-user" },
            authTokenProvider: { token },
            apiBaseURLProvider: { apiBaseURL },
            urlSession: mockSession
        )
    }

    // MARK: - Auth header attachment (security-critical)

    func testTokenAttachedForApiHostURL() async throws {
        let manager = makeManager(token: token, apiBaseURL: apiBaseURL)
        let coverURL = apiBaseURL.appendingPathComponent("/api/images/book/cover.jpg")

        let capturedAuth = Locked<String?>("sentinel")
        MockURLProtocol.requestHandler = { request in
            capturedAuth.value = request.value(forHTTPHeaderField: "Authorization")
            return (self.okResponse(for: coverURL), self.pngData())
        }

        try await manager.cacheCover(for: UUID(), from: coverURL)

        XCTAssertEqual(capturedAuth.value, "Bearer \(token)",
                       "Covers served by the API host must carry the bearer token")
    }

    /// THE security assertion: a presigned S3 URL must receive NO Authorization header.
    func testTokenNotAttachedForS3URL() async throws {
        let manager = makeManager(token: token, apiBaseURL: apiBaseURL)
        let s3URL = URL(string: "https://book-vault-media.s3.amazonaws.com/covers/x.jpg?X-Amz-Signature=abc")!

        let capturedAuth = Locked<String?>("sentinel")
        MockURLProtocol.requestHandler = { request in
            capturedAuth.value = request.value(forHTTPHeaderField: "Authorization")
            return (self.okResponse(for: s3URL), self.pngData())
        }

        try await manager.cacheCover(for: UUID(), from: s3URL)

        XCTAssertNil(capturedAuth.value,
                     "SECURITY: the bearer token must never be sent to S3 (presigned URLs)")
    }

    func testTokenNotAttachedForSameHostDifferentPort() async throws {
        let manager = makeManager(token: token, apiBaseURL: apiBaseURL)
        // Same host, different port — must NOT match the API host guard
        let otherPortURL = URL(string: "http://localhost:9999/api/images/book/cover.jpg")!

        let capturedAuth = Locked<String?>("sentinel")
        MockURLProtocol.requestHandler = { request in
            capturedAuth.value = request.value(forHTTPHeaderField: "Authorization")
            return (self.okResponse(for: otherPortURL), self.pngData())
        }

        try await manager.cacheCover(for: UUID(), from: otherPortURL)

        XCTAssertNil(capturedAuth.value, "Port is part of the host guard; a different port must not get the token")
    }

    func testNoTokenWhenProviderReturnsNil() async throws {
        // API-host URL, but no token available → no header
        let manager = makeManager(token: nil, apiBaseURL: apiBaseURL)
        let coverURL = apiBaseURL.appendingPathComponent("/api/images/book/cover.jpg")

        let capturedAuth = Locked<String?>("sentinel")
        MockURLProtocol.requestHandler = { request in
            capturedAuth.value = request.value(forHTTPHeaderField: "Authorization")
            return (self.okResponse(for: coverURL), self.pngData())
        }

        try await manager.cacheCover(for: UUID(), from: coverURL)

        XCTAssertNil(capturedAuth.value, "No token available → no Authorization header even on the API host")
    }

    // MARK: - Cache-hit guard

    func testAlreadyCachedIssuesNoNetworkRequest() async throws {
        let manager = makeManager(token: token, apiBaseURL: apiBaseURL)
        let bookId = UUID()
        let coverURL = apiBaseURL.appendingPathComponent("/api/images/book/cover.jpg")

        let requestCount = Locked(0)
        MockURLProtocol.requestHandler = { _ in
            requestCount.withLock { $0 += 1 }
            return (self.okResponse(for: coverURL), self.pngData())
        }

        // First call downloads + caches
        try await manager.cacheCover(for: bookId, from: coverURL)
        XCTAssertEqual(requestCount.value, 1)

        // Second call must short-circuit on the hasCover guard — no network
        try await manager.cacheCover(for: bookId, from: coverURL)
        XCTAssertEqual(requestCount.value, 1, "Already-cached cover must not issue a second network request")
    }

    // MARK: - Cache mechanics

    func testCacheMechanicsWriteFindDeleteClear() async throws {
        let manager = makeManager(token: token, apiBaseURL: apiBaseURL)
        let bookId = UUID()
        let coverURL = apiBaseURL.appendingPathComponent("/api/images/book/cover.jpg")

        MockURLProtocol.requestHandler = { _ in
            (self.okResponse(for: coverURL), self.pngData())
        }

        // Write
        try await manager.cacheCover(for: bookId, from: coverURL)
        XCTAssertTrue(manager.hasCover(for: bookId))
        XCTAssertNotNil(manager.localCoverURL(for: bookId))
        XCTAssertNotNil(manager.getCover(for: bookId))
        XCTAssertEqual(manager.getCacheStats().count, 1)

        // Delete one
        manager.deleteCover(for: bookId)
        XCTAssertFalse(manager.hasCover(for: bookId))
        XCTAssertNil(manager.localCoverURL(for: bookId))

        // Re-add then clear all
        try await manager.cacheCover(for: bookId, from: coverURL)
        XCTAssertTrue(manager.hasCover(for: bookId))
        manager.clearCache()
        XCTAssertFalse(manager.hasCover(for: bookId))
        XCTAssertEqual(manager.getCacheStats().count, 0)
    }
}
