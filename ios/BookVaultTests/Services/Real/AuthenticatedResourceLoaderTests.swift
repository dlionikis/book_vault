//
//  AuthenticatedResourceLoaderTests.swift
//  BookVaultTests
//
//  Phase 5: tests for the testable core of the authenticated AVAsset resource
//  loader. Drives `AuthenticatedResourceLoader` against a mock
//  `ResourceLoadingRequesting` (AVAssetResourceLoadingRequest has no public
//  initializer, so the real delegate can't be constructed in a test — the
//  AVFoundation shim is intentionally left to the device playback smoke).
//
//  Network is intercepted with MockURLProtocol (defined in APIClientRealTests).
//

import XCTest

@testable import BookVault

// MARK: - MockResourceLoadingRequest

/// Test double for a single loading request. Records completion outcome and
/// what the loader delivered, and fulfills `completionExpectation` when the
/// loader finishes (success or error), so async network/refresh flows can be
/// awaited.
final class MockResourceLoadingRequest: ResourceLoadingRequesting {
    var requestURL: URL?
    var explicitRangeHeader: String?
    var requestedByteRange: (offset: Int64, length: Int)?

    private(set) var acceptedResponse: HTTPURLResponse?
    private(set) var acceptedInfo: ResourceContentInformation?
    private(set) var respondedData: Data?
    private(set) var didComplete = false
    private(set) var completionError: Error?

    let completionExpectation = XCTestExpectation(description: "loading request completed")

    init(url: URL?) {
        requestURL = url
    }

    func acceptResponse(_ response: HTTPURLResponse, info: ResourceContentInformation) {
        acceptedResponse = response
        acceptedInfo = info
    }

    func respondWithData(_ data: Data) {
        respondedData = data
    }

    func complete() {
        didComplete = true
        completionExpectation.fulfill()
    }

    func complete(with error: Error) {
        completionError = error
        completionExpectation.fulfill()
    }
}

// MARK: - AuthenticatedResourceLoaderTests

final class AuthenticatedResourceLoaderTests: XCTestCase {
    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeLoader(
        token: String? = "test-token",
        tokenProvider: (() -> String?)? = nil,
        refresh: @escaping () async -> Bool = { false }
    ) -> AuthenticatedResourceLoader {
        AuthenticatedResourceLoader(
            tokenProvider: tokenProvider ?? { token },
            tokenRefreshHandler: refresh,
            session: mockSession,
            // Keep the concurrent-wait tiny so the "loser" of the single-flight
            // race doesn't stall the test for the production 0.5s.
            concurrentRefreshWaitNanoseconds: 20_000_000
        )
    }

    private func httpResponse(
        url: URL,
        status: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    // MARK: - 1. Scheme conversion (pure logic)

    func testConvertsBookvaultSchemeToHTTP() {
        let url = URL(string: "bookvault://example.com/audio/book.m4b")!
        let converted = AuthenticatedResourceLoader.convertToActualURL(url)
        XCTAssertEqual(converted?.scheme, "http")
        XCTAssertEqual(converted?.host, "example.com")
        XCTAssertEqual(converted?.path, "/audio/book.m4b")
    }

    func testConvertsBookvaultsSchemeToHTTPS() {
        let url = URL(string: "bookvaults://example.com/audio/book.m4b")!
        let converted = AuthenticatedResourceLoader.convertToActualURL(url)
        XCTAssertEqual(converted?.scheme, "https")
        XCTAssertEqual(converted?.host, "example.com")
    }

    func testLeavesUnknownSchemeUnchanged() {
        let url = URL(string: "https://example.com/audio/book.m4b")!
        let converted = AuthenticatedResourceLoader.convertToActualURL(url)
        XCTAssertEqual(converted?.scheme, "https")
    }

    func testStartLoadingReturnsFalseWhenNoURL() {
        let loader = makeLoader()
        let request = MockResourceLoadingRequest(url: nil)
        XCTAssertFalse(loader.startLoading(request))
    }

    // MARK: - 2. Authorization header

    func testOutgoingRequestCarriesBearerToken() {
        let loader = makeLoader(token: "my-secret-token")
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)

        var capturedAuth: String?
        MockURLProtocol.requestHandler = { req in
            capturedAuth = req.value(forHTTPHeaderField: "Authorization")
            return (self.httpResponse(url: req.url!, status: 200), Data())
        }

        XCTAssertTrue(loader.startLoading(request))
        wait(for: [request.completionExpectation], timeout: 2.0)

        XCTAssertEqual(capturedAuth, "Bearer my-secret-token")
    }

    func testMissingTokenFinishesWith401NoNetworkCall() {
        let loader = makeLoader(tokenProvider: { nil })
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)

        MockURLProtocol.requestHandler = { req in
            XCTFail("No network request should be made without a token")
            return (self.httpResponse(url: req.url!, status: 200), Data())
        }

        XCTAssertTrue(loader.startLoading(request))
        wait(for: [request.completionExpectation], timeout: 2.0)

        let error = try? XCTUnwrap(request.completionError as NSError?)
        XCTAssertEqual(error?.domain, AuthenticatedResourceLoader.errorDomain)
        XCTAssertEqual(error?.code, 401)
        XCTAssertFalse(request.didComplete)
    }

    // MARK: - 3. Range header propagation

    func testExplicitRangeHeaderIsForwarded() {
        let loader = makeLoader()
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)
        request.explicitRangeHeader = "bytes=100-199"

        var capturedRange: String?
        MockURLProtocol.requestHandler = { req in
            capturedRange = req.value(forHTTPHeaderField: "Range")
            return (self.httpResponse(url: req.url!, status: 206), Data())
        }

        loader.startLoading(request)
        wait(for: [request.completionExpectation], timeout: 2.0)

        XCTAssertEqual(capturedRange, "bytes=100-199")
    }

    func testRangeDerivedFromDataRequestWhenNoExplicitHeader() {
        let loader = makeLoader()
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)
        // offset 1000, length 512 -> bytes=1000-1511
        request.requestedByteRange = (offset: 1000, length: 512)

        var capturedRange: String?
        MockURLProtocol.requestHandler = { req in
            capturedRange = req.value(forHTTPHeaderField: "Range")
            return (self.httpResponse(url: req.url!, status: 206), Data())
        }

        loader.startLoading(request)
        wait(for: [request.completionExpectation], timeout: 2.0)

        XCTAssertEqual(capturedRange, "bytes=1000-1511")
    }

    func testExplicitRangeHeaderTakesPrecedenceOverDataRequest() {
        let loader = makeLoader()
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)
        request.explicitRangeHeader = "bytes=5-10"
        request.requestedByteRange = (offset: 1000, length: 512)

        var capturedRange: String?
        MockURLProtocol.requestHandler = { req in
            capturedRange = req.value(forHTTPHeaderField: "Range")
            return (self.httpResponse(url: req.url!, status: 206), Data())
        }

        loader.startLoading(request)
        wait(for: [request.completionExpectation], timeout: 2.0)

        XCTAssertEqual(capturedRange, "bytes=5-10")
    }

    // MARK: - Success delivers data + content info

    func testSuccessDeliversDataAndParsesContentRange() {
        let loader = makeLoader()
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)
        let body = Data("audio-bytes".utf8)

        MockURLProtocol.requestHandler = { req in
            let response = self.httpResponse(
                url: req.url!,
                status: 206,
                headers: ["Content-Type": "audio/mp4", "Content-Range": "bytes 0-10/123456789"]
            )
            return (response, body)
        }

        loader.startLoading(request)
        wait(for: [request.completionExpectation], timeout: 2.0)

        XCTAssertTrue(request.didComplete)
        XCTAssertNil(request.completionError)
        XCTAssertEqual(request.respondedData, body)
        XCTAssertEqual(request.acceptedInfo?.contentLength, 123_456_789)
        XCTAssertEqual(request.acceptedInfo?.isByteRangeAccessSupported, true)
    }

    // MARK: - Non-2xx (non-401) is an error

    func testServerErrorFinishesWithError() {
        let loader = makeLoader()
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)

        MockURLProtocol.requestHandler = { req in
            (self.httpResponse(url: req.url!, status: 500), Data())
        }

        loader.startLoading(request)
        wait(for: [request.completionExpectation], timeout: 2.0)

        let error = request.completionError as NSError?
        XCTAssertEqual(error?.domain, AuthenticatedResourceLoader.errorDomain)
        XCTAssertEqual(error?.code, 500)
        XCTAssertFalse(request.didComplete)
    }

    // MARK: - 4. 401 -> refresh succeeds -> retry with new token

    func testUnauthorizedRefreshesAndRetriesWithNewToken() {
        // tokenProvider returns the "old" token first, then a "new" token after
        // a successful refresh flips the flag.
        var refreshed = false
        let refreshExpectation = XCTestExpectation(description: "refresh called")

        let loader = AuthenticatedResourceLoader(
            tokenProvider: { refreshed ? "new-token" : "old-token" },
            tokenRefreshHandler: {
                refreshed = true
                refreshExpectation.fulfill()
                return true
            },
            session: mockSession,
            concurrentRefreshWaitNanoseconds: 20_000_000
        )

        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)

        var seenAuthHeaders: [String] = []
        let headerLock = NSLock()
        MockURLProtocol.requestHandler = { req in
            let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
            headerLock.lock()
            seenAuthHeaders.append(auth)
            let attempt = seenAuthHeaders.count
            headerLock.unlock()
            // First attempt (old token) -> 401; retry (new token) -> 200.
            let status = attempt == 1 ? 401 : 200
            return (self.httpResponse(url: req.url!, status: status), Data())
        }

        loader.startLoading(request)
        wait(for: [refreshExpectation, request.completionExpectation], timeout: 3.0)

        XCTAssertTrue(request.didComplete, "Retry after refresh should succeed")
        XCTAssertNil(request.completionError)
        headerLock.lock()
        let headers = seenAuthHeaders
        headerLock.unlock()
        XCTAssertEqual(headers, ["Bearer old-token", "Bearer new-token"])
    }

    // MARK: - 5. 401 -> refresh fails -> error (domain/code)

    func testUnauthorizedRefreshFailsFinishesWith401() {
        let loader = makeLoader(token: "stale", refresh: { false })
        let request = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)

        MockURLProtocol.requestHandler = { req in
            (self.httpResponse(url: req.url!, status: 401), Data())
        }

        loader.startLoading(request)
        wait(for: [request.completionExpectation], timeout: 3.0)

        let error = request.completionError as NSError?
        XCTAssertEqual(error?.domain, AuthenticatedResourceLoader.errorDomain)
        XCTAssertEqual(error?.code, 401)
        XCTAssertFalse(request.didComplete)
    }

    // MARK: - 6. Single-flight: concurrent 401s trigger exactly one refresh

    func testConcurrent401sTriggerSingleRefresh() {
        // Both requests hit 401 on their first attempt. The refresh handler
        // blocks until BOTH have arrived, guaranteeing the second 401 is
        // processed while the first refresh is still in flight — the condition
        // under which the single-flight lock must suppress the second refresh.
        let refreshCount = AtomicCounter()
        let bothArrived = XCTestExpectation(description: "both requests hit 401")
        var arrivedCount = 0
        let arrivedLock = NSLock()

        let loader = AuthenticatedResourceLoader(
            tokenProvider: { "token" },
            tokenRefreshHandler: {
                refreshCount.increment()
                // Hold the refresh open long enough for the concurrent request
                // to observe isRefreshing == true.
                try? await Task.sleep(nanoseconds: 200_000_000)
                return true
            },
            session: mockSession,
            // Loser waits longer than the refresh above so it reuses the token
            // after the refresh completes, rather than racing it.
            concurrentRefreshWaitNanoseconds: 400_000_000
        )

        let firstAttempt = AtomicCounter()
        MockURLProtocol.requestHandler = { req in
            let attempt = firstAttempt.increment()
            if attempt <= 2 {
                // First hit for each of the two requests -> 401.
                arrivedLock.lock()
                arrivedCount += 1
                if arrivedCount == 2 { bothArrived.fulfill() }
                arrivedLock.unlock()
                return (self.httpResponse(url: req.url!, status: 401), Data())
            }
            // Retries -> 200.
            return (self.httpResponse(url: req.url!, status: 200), Data())
        }

        let requestA = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/a.m4b")!)
        let requestB = MockResourceLoadingRequest(url: URL(string: "bookvaults://example.com/b.m4b")!)

        loader.startLoading(requestA)
        loader.startLoading(requestB)

        wait(for: [bothArrived], timeout: 3.0)
        wait(for: [requestA.completionExpectation, requestB.completionExpectation], timeout: 5.0)

        XCTAssertEqual(refreshCount.value, 1, "Concurrent 401s must trigger exactly one token refresh")
        XCTAssertTrue(requestA.didComplete)
        XCTAssertTrue(requestB.didComplete)
    }
}

// MARK: - AtomicCounter

/// Minimal thread-safe counter for asserting invocation counts across the
/// session's completion queue and the refresh `Task`.
private final class AtomicCounter {
    private var count = 0
    private let lock = NSLock()

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
