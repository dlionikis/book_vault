//
//  TokenRefreshConcurrencyTests.swift
//  BookVaultTests
//
//  Tier 1 regression tests for the "logged out every ~2 hours" bug.
//  See docs/plans/ios-audio-session-persistence-plan.md.
//
//  These pin down the 401 -> refresh -> retry coordination that
//  APIClientRealTests never exercised. Each test corresponds to one defect
//  from that investigation; all four are fixed, and these keep them fixed:
//
//    Defect 1 - check-then-act race in APIClient.attemptTokenRefresh(). The
//               claim-or-join decision spanned two actor hops, so concurrent
//               401s could both refresh. Because the backend rotates refresh
//               tokens on every use, the second refresh would present an
//               already-consumed token and log the user out. (Latent in
//               practice — never reproduced — but closed anyway.)
//
//    Defect 2 - lost wakeup: waiters registered from a detached Task could be
//               appended after the waiter list was drained, so that
//               continuation was never resumed and the request hung forever.
//               (Also latent; also closed.)
//
//    Defect 3 - CONFIRMED TRIGGER. AuthenticatedResourceLoader did not share
//               the coordinator; its concurrent branch slept a fixed interval
//               and then only checked that *a* token existed. A refresh slower
//               than that timer meant retrying with the stale token, a second
//               401, and playback torn down.
//
//    Defect 4 - CONFIRMED AMPLIFIER. forceLogoutHandler fired per failing
//               request, so one refresh failure produced N logouts for N
//               in-flight requests.
//
//  Network is intercepted with MockURLProtocol (defined in APIClientRealTests).
//

import XCTest

@testable import BookVault

// MARK: - Test support

/// Thread-safe counter. `MockURLProtocol` invokes its handler on multiple
/// URLSession delegate queues, and these tests deliberately drive concurrent
/// requests, so every shared tally has to be synchronized.
private final class AtomicCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Thread-safe string accumulator, for recording the tokens seen per request.
private final class AtomicLog: @unchecked Sendable {
    private var items: [String] = []
    private let lock = NSLock()

    func append(_ item: String) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

/// A rotating refresh token, mirroring server-side rotation.
///
/// Exists because the Swift 6 language mode forbids `NSLock.lock()` in an async
/// context and rejects mutating captured `var`s from concurrent code. The
/// semantics are deliberately identical to the `NSLock` + `var` code this
/// replaced: **one** atomic read-then-rotate, so two concurrent callers can
/// never observe the same token. That indivisibility is the whole point of the
/// test — a version that read and wrote under separate lock acquisitions would
/// still compile and would silently stop testing anything.
private final class RotatingToken: @unchecked Sendable {
    private var generation = 1
    private var current: String
    private let lock = NSLock()

    init(_ initial: String) { current = initial }

    /// Atomically return the token a caller would present, then rotate it.
    func presentAndRotate() -> String {
        lock.lock()
        defer { lock.unlock() }
        let presented = current
        generation += 1
        current = "refresh-token-\(generation)"
        return presented
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

// MARK: - TokenRefreshConcurrencyTests

/// `@unchecked Sendable` so test bodies can capture `self` inside the
/// `@Sendable` closures these tests hand to URLProtocol / refresh handlers.
/// XCTest drives one instance per test method and never concurrently, so
/// there is no cross-test sharing to race on.
final class TokenRefreshConcurrencyTests: XCTestCase, @unchecked Sendable {
    private var mockSession: URLSession!
    private var sut: APIClient!

    /// Concurrency level for the racing-request tests. High enough to make the
    /// race window reliably observable, low enough to stay fast.
    private let concurrentRequestCount = 8

    override func setUp() async throws {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        sut = APIClient(baseURL: URL(string: "http://localhost:3000")!, session: mockSession)
        sut.forceLogoutHandler = { @Sendable in }
        sut.accessToken = "expired-token"
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        sut = nil
        mockSession = nil
    }

    // MARK: - Helpers

    private func booksPayload() -> Data {
        let json: [String: Any] = [
            "books": [],
            "pagination": ["page": 1, "limit": 20, "total": 0, "totalPages": 0]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func response(_ code: Int, for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost:3000")!,
            statusCode: code,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    /// Serve 401 to anything bearing a stale token and 200 once the client
    /// presents `validToken`. Mirrors how the real backend behaves after the
    /// access token expires mid-session.
    private func installExpiringTokenHandler(validToken: String) {
        MockURLProtocol.requestHandler = { [self] request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            let code = (auth == "Bearer \(validToken)") ? 200 : 401
            return (response(code, for: request), code == 200 ? booksPayload() : Data("{}".utf8))
        }
    }

    // MARK: - Defect 1: single-flight under concurrency

    /// Many requests 401 at the same instant. Exactly one token refresh should
    /// occur; the rest must reuse its result.
    ///
    /// Guards Defect 1: a check-then-act gap would let several callers refresh,
    /// and each extra refresh consumes a rotated refresh token — the concrete
    /// path to being logged out mid-playback.
    func testConcurrentUnauthorizedRequestsTriggerExactlyOneRefresh() async {
        let refreshCount = AtomicCounter()
        installExpiringTokenHandler(validToken: "fresh-token")

        sut.tokenRefreshHandler = { @Sendable [self] in
            _ = refreshCount.increment()
            // Model real refresh latency so the race window is open, and so a
            // second entrant has time to slip through the check-then-act gap.
            try? await Task.sleep(nanoseconds: 50_000_000)
            sut.accessToken = "fresh-token"
            return true
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< concurrentRequestCount {
                group.addTask { [self] in
                    _ = try? await sut.fetchBooks()
                }
            }
            await group.waitForAll()
        }

        XCTAssertEqual(
            refreshCount.current,
            1,
            """
            Expected exactly one refresh across \(concurrentRequestCount) concurrent 401s, \
            got \(refreshCount.current). Each surplus refresh consumes a rotated refresh \
            token and forces a logout (Defect 1).
            """
        )
    }

    /// A request already in flight when a refresh completes still comes back 401
    /// — its response was decided by the server before the token was swapped.
    /// That 401 is stale information and must NOT start a second refresh.
    ///
    /// Guards Defect 5, which CI caught and a fast local machine did not: the
    /// original fix produced 2 refreshes here because the coordinator was empty
    /// by the time the late 401 arrived, so there was nothing to join. In
    /// production each surplus refresh burns a rotated refresh token.
    ///
    /// The stagger is forced rather than left to scheduling luck, so this is
    /// deterministic on any machine speed.
    func testLateArriving401DoesNotTriggerSecondRefresh() async {
        let refreshCount = AtomicCounter()

        // Sequencing is explicit rather than time-based, so the interleaving is
        // identical on a fast laptop and a slow CI runner.
        let refreshHasCompleted = XCTestExpectation(description: "refresh completed")

        // Every request 401s. The token value is irrelevant here: the point is
        // that a request issued BEFORE the refresh can still be answered 401 by
        // the server, and that late 401 must not start another refresh.
        MockURLProtocol.requestHandler = { [self] request in
            (response(401, for: request), Data("{}".utf8))
        }

        sut.tokenRefreshHandler = { @Sendable [self] in
            _ = refreshCount.increment()
            sut.accessToken = "fresh-token"
            refreshHasCompleted.fulfill()
            return true
        }

        // Drive one legitimate refresh to completion. This request ends up
        // throwing (the retry also 401s), which is fine — we only need the
        // refresh to have happened and the generation to have advanced.
        _ = try? await sut.fetchBooks()
        await fulfillment(of: [refreshHasCompleted], timeout: 2.0)

        XCTAssertEqual(refreshCount.current, 1, "Setup should have produced exactly one refresh")

        // Now simulate a request that was issued BEFORE that refresh and whose
        // 401 arrives only now: it carries the pre-refresh generation.
        let staleGeneration: UInt64 = 0
        let recovered = await sut.refreshForTesting(observedGeneration: staleGeneration)

        XCTAssertTrue(
            recovered,
            "A caller whose token was already refreshed should be told to retry, not fail"
        )
        XCTAssertEqual(
            refreshCount.current,
            1,
            """
            Expected still exactly one refresh, got \(refreshCount.current). A 401 that \
            arrived after the token was already refreshed triggered a redundant refresh, \
            consuming a rotated refresh token for nothing (Defect 5).
            """
        )
    }

    /// The rotation consequence stated directly: a refresh token must never be
    /// submitted to the refresh endpoint twice.
    ///
    /// Same underlying guarantee as the test above, asserted on the mechanism
    /// that actually causes the logout.
    func testRefreshTokenIsNeverConsumedTwice() async {
        let submitted = AtomicLog()
        let refreshToken = RotatingToken("refresh-token-1")

        installExpiringTokenHandler(validToken: "fresh-token")

        sut.tokenRefreshHandler = { @Sendable [self] in
            // Read-then-rotate, exactly as the server-side rotation behaves,
            // and atomically — see RotatingToken.
            let presented = refreshToken.presentAndRotate()

            submitted.append(presented)
            try? await Task.sleep(nanoseconds: 50_000_000)
            sut.accessToken = "fresh-token"
            return true
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< concurrentRequestCount {
                group.addTask { [self] in
                    _ = try? await sut.fetchBooks()
                }
            }
            await group.waitForAll()
        }

        let presentedTokens = submitted.all
        XCTAssertEqual(
            presentedTokens.count,
            Set(presentedTokens).count,
            """
            A refresh token was presented more than once: \(presentedTokens). \
            The backend rotates on every use, so the replayed token is rejected \
            and the user is logged out (Defect 1).
            """
        )
    }

    // MARK: - Defect 2: lost wakeup

    /// Guards Defect 2: if waiter registration were not synchronous with the
    /// coordinator, a very fast refresh could drain the waiter list before a
    /// waiter registered, and that continuation would never be resumed.
    ///
    /// A regression here manifests as a HANG, not a false assertion — the
    /// timeout is the assertion. Every request must return, success or failure.
    func testConcurrentRequestsAllReturnWhenRefreshCompletesImmediately() async {
        installExpiringTokenHandler(validToken: "fresh-token")

        // No sleep: the refresh resolves as fast as possible, maximizing the
        // chance it drains `waiters` before a waiter is appended.
        sut.tokenRefreshHandler = { @Sendable [self] in
            sut.accessToken = "fresh-token"
            return true
        }

        let completed = AtomicCounter()
        let allReturned = expectation(description: "every concurrent request returned")
        allReturned.expectedFulfillmentCount = concurrentRequestCount

        for _ in 0 ..< concurrentRequestCount {
            Task { [self] in
                _ = try? await sut.fetchBooks()
                _ = completed.increment()
                allReturned.fulfill()
            }
        }

        await fulfillment(of: [allReturned], timeout: 5.0)

        XCTAssertEqual(
            completed.current,
            concurrentRequestCount,
            """
            Only \(completed.current)/\(concurrentRequestCount) requests returned. \
            A continuation was registered after completeRefresh() drained the waiter \
            list and is never resumed, so the request hangs forever (Defect 2).
            """
        )
    }

    // MARK: - Defect 4: genuine failure must still log out, exactly once

    /// A real credential failure must still force exactly one logout.
    ///
    /// Two-sided guarantee: the logout must still happen (the fix must not
    /// become "tokens never expire"), and it must happen only once no matter
    /// how many requests are in flight. Before the fix this produced 8 logouts
    /// for 8 concurrent requests.
    func testFailedRefreshForcesExactlyOneLogout() async {
        let logoutCount = AtomicCounter()
        let logoutLock = NSLock()

        // Always 401: the credential is genuinely revoked.
        MockURLProtocol.requestHandler = { [self] request in
            (response(401, for: request), Data("{}".utf8))
        }

        sut.tokenRefreshHandler = { @Sendable in
            try? await Task.sleep(nanoseconds: 20_000_000)
            return false
        }
        sut.forceLogoutHandler = { @Sendable in
            logoutLock.lock()
            defer { logoutLock.unlock() }
            _ = logoutCount.increment()
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< concurrentRequestCount {
                group.addTask { [self] in
                    _ = try? await sut.fetchBooks()
                }
            }
            await group.waitForAll()
        }

        XCTAssertEqual(
            logoutCount.current,
            1,
            """
            Expected exactly one forced logout for a genuinely revoked credential, \
            got \(logoutCount.current).
            """
        )
    }
}

// MARK: - ResourceLoaderRefreshConcurrencyTests

/// Defect 3: the AVPlayer streaming path has its own refresh implementation
/// that does not share the coordinator.
final class ResourceLoaderRefreshConcurrencyTests: XCTestCase {
    private var mockSession: URLSession!

    override func setUp() async throws {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        mockSession = nil
    }

    /// Two concurrent 401s in the streaming path, where the refresh takes far
    /// longer than the fixed wait the loader used to rely on (300ms vs 50ms).
    ///
    /// This is the reported bug. Previously the second request woke early, saw
    /// that *a* token existed (the stale one), retried with it, took a second
    /// 401, and playback was torn down. The retry must now carry the refreshed
    /// token, which requires waiting on refresh completion rather than a timer.
    func testConcurrentStreamRequestRetriesWithRefreshedTokenNotStaleToken() async {
        // `Locked` rather than NSLock + a captured `var`: the Swift 6 language
        // mode forbids `lock()` in async contexts and rejects mutating captured
        // vars from concurrent code. Same semantics, same timing.
        let currentToken = Locked("stale-token")

        let retryTokens = AtomicLog()

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? "none"
            let presented = auth.replacingOccurrences(of: "Bearer ", with: "")
            retryTokens.append(presented)

            let isValid = (presented == "fresh-token")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: isValid ? 200 : 401,
                httpVersion: nil,
                headerFields: isValid
                    ? ["Content-Type": "audio/mpeg", "Content-Range": "bytes 0-3/4"]
                    : ["Content-Type": "application/json"]
            )!
            return (response, isValid ? Data([0x1, 0x2, 0x3, 0x4]) : Data("{}".utf8))
        }

        // Refresh takes 300ms. Before the fix the loader waited a fixed 50ms and
        // then merely checked that *a* token existed, so the concurrent request
        // woke early and retried with the stale one. It must now wait for the
        // refresh to actually complete, however long that takes.
        let loader = AuthenticatedResourceLoader(
            tokenProvider: { currentToken.value },
            tokenRefreshHandler: {
                try? await Task.sleep(nanoseconds: 300_000_000)
                currentToken.value = "fresh-token"
                return true
            },
            session: mockSession
        )

        let first = MockResourceLoadingRequest(url: URL(string: "bookvault://localhost:3000/api/stream/a")!)
        let second = MockResourceLoadingRequest(url: URL(string: "bookvault://localhost:3000/api/stream/b")!)

        loader.startLoading(first)
        loader.startLoading(second)

        await fulfillment(
            of: [first.completionExpectation, second.completionExpectation],
            timeout: 5.0
        )

        XCTAssertNil(
            first.completionError,
            "First stream request failed: \(String(describing: first.completionError))"
        )
        XCTAssertNil(
            second.completionError,
            """
            Second stream request failed. It woke from its fixed wait before the \
            refresh finished, retried with the stale token, and took a second 401 — \
            which is what stops audio mid-playback (Defect 3). \
            Tokens presented, in order: \(retryTokens.all)
            """
        )
    }

    /// The architectural fix: `APIClient` and `AuthenticatedResourceLoader` must
    /// share one coordinator, so a streaming 401 and an API 401 arriving together
    /// produce ONE refresh between them.
    ///
    /// This is the case that broke in production and that neither PR #56 nor
    /// PR #66 covered — each hardened one path while leaving the other with its
    /// own independent refresh. Two refreshes means the rotated refresh token is
    /// consumed twice, the second is rejected, and the user is logged out.
    func testStreamingAndAPIPathsShareOneRefresh() async {
        let refreshCount = AtomicCounter()
        let currentToken = Locked("stale-token")

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let presented = auth.replacingOccurrences(of: "Bearer ", with: "")
            let isValid = (presented == "fresh-token")

            // The streaming path wants audio bytes; the API path wants JSON.
            let isStream = request.url?.path.contains("/api/stream/") == true
            let headers: [String: String] = isValid && isStream
                ? ["Content-Type": "audio/mpeg", "Content-Range": "bytes 0-3/4"]
                : ["Content-Type": "application/json"]

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: isValid ? 200 : 401,
                httpVersion: nil,
                headerFields: headers
            )!

            if !isValid { return (response, Data("{}".utf8)) }
            if isStream { return (response, Data([0x1, 0x2, 0x3, 0x4])) }

            let json: [String: Any] = [
                "books": [],
                "pagination": ["page": 1, "limit": 20, "total": 0, "totalPages": 0]
            ]
            return (response, try! JSONSerialization.data(withJSONObject: json))
        }

        // One coordinator, both paths — exactly how production is wired.
        let sharedCoordinator = TokenRefreshCoordinator()

        let refresh: @Sendable () async -> Bool = {
            _ = refreshCount.increment()
            try? await Task.sleep(nanoseconds: 200_000_000)
            currentToken.value = "fresh-token"
            return true
        }

        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            session: mockSession,
            refreshCoordinator: sharedCoordinator
        )
        client.forceLogoutHandler = { @Sendable in }
        client.accessToken = "stale-token"
        client.tokenRefreshHandler = { @Sendable in
            let ok = await refresh()
            client.accessToken = currentToken.value
            return ok
        }

        let loader = AuthenticatedResourceLoader(
            tokenProvider: { currentToken.value },
            tokenRefreshHandler: refresh,
            session: mockSession,
            refreshCoordinator: sharedCoordinator
        )

        let streamRequest = MockResourceLoadingRequest(
            url: URL(string: "bookvault://localhost:3000/api/stream/a")!
        )

        // Fire both paths into a 401 at the same moment.
        async let apiCall: Void = {
            _ = try? await client.fetchBooks()
        }()
        loader.startLoading(streamRequest)
        await apiCall
        await fulfillment(of: [streamRequest.completionExpectation], timeout: 5.0)

        XCTAssertEqual(
            refreshCount.current,
            1,
            """
            Expected the streaming and API paths to share ONE refresh, got \
            \(refreshCount.current). Two refreshes double-consume the rotated \
            refresh token and log the user out — the exact gap that survived \
            PR #56 and PR #66.
            """
        )
        XCTAssertNil(streamRequest.completionError, "Stream request should have succeeded after the shared refresh")
    }
}
