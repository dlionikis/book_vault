//
//  AuthenticatedResourceLoader.swift
//  BookVault
//
//  Testable core of AuthenticatedAVAssetResourceLoaderDelegate.
//
//  AVAssetResourceLoadingRequest has no public initializer, so its behavior
//  cannot be exercised in a unit test. This file extracts everything the
//  delegate actually does — custom-scheme conversion, authenticated URLRequest
//  construction with a Range header, and the 401 → refresh → retry state machine
//  with its single-flight lock — into `AuthenticatedResourceLoader`, which
//  operates on the `ResourceLoadingRequesting` protocol instead of a concrete
//  AVFoundation type. The AVFoundation delegate is a thin shim that conforms the
//  real loading request to this protocol (see
//  AuthenticatedAVAssetResourceLoaderDelegate.swift).
//

import Foundation

// MARK: - ResourceLoadingRequesting

/// The subset of `AVAssetResourceLoadingRequest` the loader depends on.
///
/// A concrete `AVAssetResourceLoadingRequest` is adapted to this protocol by the
/// delegate shim; tests supply a mock conformance.
/// `Sendable` because these objects are handed to `Task`s that outlive the
/// synchronous `startLoading` call AVFoundation requires.
///
/// This is a real assertion, not a formality, so it is worth stating why it
/// holds: AVFoundation vends one loading request per resource and drives it
/// from a single serial loader queue. This type never fans a request out to
/// multiple tasks — `startLoading` and `handleUnauthorized` each spawn exactly
/// one `Task` per request, and the retry path runs only after the first
/// attempt has finished. So a given request is only ever touched from one
/// place at a time.
///
/// The production conformer is `AVAssetResourceLoadingRequest` (an Apple class
/// that predates `Sendable` and is not annotated), which is why the conformance
/// has to be `@unchecked` at that site rather than checked here.
protocol ResourceLoadingRequesting: AnyObject, Sendable {
    /// The original (custom-scheme) request URL.
    var requestURL: URL? { get }

    /// An explicit `Range` header on the incoming request, if present.
    var explicitRangeHeader: String? { get }

    /// The byte range implied by the data request, if there is one.
    /// `length` mirrors `AVAssetResourceLoadingDataRequest.requestedLength` (an `Int`).
    var requestedByteRange: (offset: Int64, length: Int)? { get }

    /// Record the successful HTTP response and populate the content-information
    /// request (if the underlying request has one).
    func acceptResponse(_ response: HTTPURLResponse, info: ResourceContentInformation)

    /// Deliver body bytes to the data request (if there is one).
    func respondWithData(_ data: Data)

    /// Complete the request successfully.
    func complete()

    /// Complete the request with an error.
    func complete(with error: Error)
}

// MARK: - ResourceContentInformation

/// Content metadata written back to a loading request's content-information request.
struct ResourceContentInformation {
    let contentType: String?
    let isByteRangeAccessSupported: Bool
    let contentLength: Int64
}

// MARK: - AuthenticatedResourceLoader

/// Core, AVFoundation-free implementation of the authenticated resource loader.
///
/// On 401 the loader refreshes the access token and retries once. Refreshes are
/// coordinated through a shared `TokenRefreshCoordinator`, so a concurrent 401 —
/// from another stream request *or* from the JSON API path — joins the in-flight
/// refresh and resumes when it genuinely completes, then retries with the new
/// token.
/// `@unchecked Sendable` because AVFoundation requires `startLoading` to return
/// synchronously, so the actual work runs in a `Task` that captures `self`.
///
/// The guarantee is real rather than asserted: every stored property is a `let`
/// holding a `Sendable` value, except `loadingTasks`, whose every access is
/// already guarded by `tasksLock`. There is no unsynchronized mutable state to
/// race on. `@unchecked` is needed only because the compiler cannot verify the
/// lock discipline itself.
final class AuthenticatedResourceLoader: @unchecked Sendable {
    /// How many times to re-read the token when the keychain reports the device
    /// is locked, and how long to wait between attempts.
    ///
    /// The keychain is briefly unreadable around lock/unlock transitions even
    /// for `AfterFirstUnlock` items (notably before the first unlock after a
    /// reboot). Failing the byte-range request immediately turns that blip into
    /// stopped playback, so a short bounded retry is worth more than failing
    /// fast here. Bounded, because if the device is genuinely locked pre-first-
    /// unlock, no amount of waiting helps and the request should surface an
    /// error rather than hang AVFoundation's loader queue.
    static let lockedTokenRetryLimit = 3
    static let lockedTokenRetryDelay: TimeInterval = 0.5

    private let tokenProvider: @Sendable () -> String?
    private let tokenRefreshHandler: @Sendable () async -> Bool
    private let session: URLSession

    /// Reports whether the last token read failed because the device was
    /// locked, so the loader can retry instead of failing the request. Defaults
    /// to "never locked", which preserves the behavior of callers (and tests)
    /// that only supply a `tokenProvider`.
    private let tokenIsLocked: @Sendable () -> Bool

    /// Sleep hook, injectable so tests do not pay the retry delay in real time.
    private let sleep: @Sendable (TimeInterval) async -> Void

    /// Single-flight refresh coordination, shared with `APIClient` so a
    /// streaming 401 and an API 401 join the same refresh rather than each
    /// starting one and double-consuming the rotated refresh token.
    private let refreshCoordinator: TokenRefreshCoordinator

    private var loadingTasks: [String: URLSessionDataTask] = [:]
    private let tasksLock = NSLock()

    /// Domain used for the NSErrors this loader emits. Kept identical to the
    /// original delegate so existing error handling / logging is unaffected.
    static let errorDomain = "AuthenticatedAVAssetResourceLoaderDelegate"

    init(
        tokenProvider: @escaping @Sendable () -> String?,
        tokenRefreshHandler: @escaping @Sendable () async -> Bool,
        session: URLSession,
        refreshCoordinator: TokenRefreshCoordinator = TokenRefreshCoordinator(),
        tokenIsLocked: @escaping @Sendable () -> Bool = { false },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.tokenProvider = tokenProvider
        self.tokenRefreshHandler = tokenRefreshHandler
        self.session = session
        self.refreshCoordinator = refreshCoordinator
        self.tokenIsLocked = tokenIsLocked
        self.sleep = sleep
    }

    /// Read the access token, retrying briefly if the keychain is locked.
    ///
    /// Async so the retry can suspend rather than block AVFoundation's loader
    /// queue.
    private func currentTokenAwaitingUnlock() async -> String? {
        for attempt in 0 ..< Self.lockedTokenRetryLimit {
            if let token = tokenProvider() { return token }
            guard tokenIsLocked() else { return nil }

            DebugLogger.auth(
                "Resource loader: token unreadable (device locked) - " +
                    "retry \(attempt + 1)/\(Self.lockedTokenRetryLimit)"
            )
            await sleep(Self.lockedTokenRetryDelay)
        }
        return tokenProvider()
    }

    // MARK: - Entry point

    /// Begin handling a loading request. Returns `false` if the request is
    /// unusable (no URL, or scheme conversion fails); otherwise starts the
    /// network request and returns `true`.
    @discardableResult
    func startLoading(_ request: ResourceLoadingRequesting) -> Bool {
        guard let url = request.requestURL else {
            DebugLogger.error("Resource loader: No URL in request")
            return false
        }

        DebugLogger.verbose("Resource loader: URL = \(url.absoluteString)")

        guard let actualURL = Self.convertToActualURL(url) else {
            DebugLogger.error("Resource loader: Failed to convert URL")
            return false
        }

        DebugLogger.verbose("Resource loader: Actual URL = \(actualURL.absoluteString)")

        // Read the token generation before dispatching, so a 401 caused by a
        // refresh that landed mid-flight is recognized as stale and retried
        // rather than triggering a second, redundant refresh. `startLoading` must
        // stay synchronous for AVFoundation, so the capture happens in a Task.
        Task {
            let generation = await refreshCoordinator.currentGeneration()

            // Wait out a locked keychain before issuing the request. Without
            // this, locking the screen mid-playback makes the token read return
            // nil and the next byte-range request fails instantly — which is
            // what stopped playback on lock.
            //
            // The resolved token is passed down rather than re-read: re-reading
            // would both waste a keychain round-trip and reintroduce the bug,
            // since the value could go unreadable again between the two reads.
            guard let token = await currentTokenAwaitingUnlock() else {
                // Genuinely unavailable — either absent (logged out) or still
                // locked after the bounded retry. Fail here rather than passing
                // `nil` down, which would trigger a redundant re-read.
                DebugLogger.error("Resource loader: No authentication token available")
                request.complete(with: NSError(
                    domain: Self.errorDomain,
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No authentication token"]
                ))
                return
            }

            executeRequest(
                actualURL: actualURL,
                loadingRequest: request,
                originalURL: url,
                isRetry: false,
                observedGeneration: generation,
                token: token
            )
        }
        return true
    }

    /// Cancel any in-flight task for the given original (custom-scheme) URL.
    func cancelLoading(for url: URL) {
        tasksLock.lock()
        let task = loadingTasks.removeValue(forKey: url.absoluteString)
        tasksLock.unlock()
        task?.cancel()
    }

    // MARK: - Scheme conversion

    /// Convert a custom-scheme URL back to its actual http/https form.
    /// `bookvault://` → `http://`, `bookvaults://` → `https://`.
    static func convertToActualURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if components.scheme == "bookvault" {
            components.scheme = "http"
        } else if components.scheme == "bookvaults" {
            components.scheme = "https"
        }

        return components.url
    }

    // MARK: - Request construction

    /// Build an authenticated `URLRequest`, carrying the auth token and a Range
    /// header (explicit if present, otherwise derived from the data request).
    /// Returns `nil` when no token is available.
    /// - Parameter token: an already-resolved token. Pass `nil` to read one now
    ///   (the retry path, which runs after a refresh has just stored a fresh
    ///   token).
    func makeAuthenticatedRequest(
        url: URL,
        for loadingRequest: ResourceLoadingRequesting,
        token: String? = nil
    ) -> URLRequest? {
        guard let token = token ?? tokenProvider() else {
            DebugLogger.error("Resource loader: No authentication token available")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let rangeHeader = loadingRequest.explicitRangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        } else if let range = loadingRequest.requestedByteRange {
            let rangeEnd = range.offset + Int64(range.length) - 1
            request.setValue("bytes=\(range.offset)-\(rangeEnd)", forHTTPHeaderField: "Range")
        }

        return request
    }

    // MARK: - Execution

    /// - Parameter observedGeneration: token generation captured before this
    ///   request was issued, or `nil` if not yet known (the first attempt, which
    ///   reads it lazily on 401). Used to detect a 401 that is stale because a
    ///   refresh completed while the request was in flight.
    /// - Parameter token: a token already resolved by the caller, or `nil` to
    ///   read one here.
    private func executeRequest(
        actualURL: URL,
        loadingRequest: ResourceLoadingRequesting,
        originalURL: URL,
        isRetry: Bool,
        observedGeneration: UInt64? = nil,
        token: String? = nil
    ) {
        guard let request = makeAuthenticatedRequest(url: actualURL, for: loadingRequest, token: token) else {
            loadingRequest.complete(with: NSError(
                domain: Self.errorDomain,
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No authentication token"]
            ))
            return
        }

        DebugLogger.verbose("Resource loader: Starting request\(isRetry ? " (retry)" : "")...")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                DebugLogger.error("Resource loader: Request failed", error: error)
                loadingRequest.complete(with: error)
                self.removeTask(for: originalURL)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DebugLogger.error("Resource loader: Invalid response type")
                loadingRequest.complete(with: NSError(
                    domain: Self.errorDomain,
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                ))
                self.removeTask(for: originalURL)
                return
            }

            DebugLogger.verbose("Resource loader: Response status \(httpResponse.statusCode)")

            // 401 → refresh token and retry (only once).
            if httpResponse.statusCode == 401, !isRetry {
                DebugLogger.auth("Resource loader: Received 401 - attempting token refresh...")
                self.handleUnauthorized(
                    actualURL: actualURL,
                    loadingRequest: loadingRequest,
                    originalURL: originalURL,
                    observedGeneration: observedGeneration
                )
                return
            }

            // Other non-2xx → error.
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                DebugLogger.error("Resource loader: HTTP error \(httpResponse.statusCode)")
                loadingRequest.complete(with: NSError(
                    domain: Self.errorDomain,
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                ))
                self.removeTask(for: originalURL)
                return
            }

            // Success.
            loadingRequest.acceptResponse(httpResponse, info: Self.contentInformation(from: httpResponse))

            if let data {
                loadingRequest.respondWithData(data)
            }

            loadingRequest.complete()
            DebugLogger.verbose("Resource loader: Request completed successfully")
            self.removeTask(for: originalURL)
        }

        tasksLock.lock()
        loadingTasks[originalURL.absoluteString] = task
        tasksLock.unlock()
        task.resume()
    }

    // MARK: - 401 handling

    private func handleUnauthorized(
        actualURL: URL,
        loadingRequest: ResourceLoadingRequesting,
        originalURL: URL,
        observedGeneration: UInt64?
    ) {
        Task {
            // Await the refresh itself, whether we start it or join one already
            // running — including one started by the JSON API path, since the
            // coordinator is shared app-wide.
            //
            // This previously slept a fixed interval and then checked only that
            // *a* token existed. When a refresh outran that timer (routine on
            // cellular), the request retried with the STALE token, took a second
            // 401, and tore down playback. That was the "audio stops every ~2
            // hours" bug. Waiting on completion is what actually fixes it.
            let handler = tokenRefreshHandler
            let refreshSucceeded = await refreshCoordinator.refresh(
                observedGeneration: observedGeneration,
                using: handler
            )

            if refreshSucceeded {
                DebugLogger.auth("Resource loader: Token refresh succeeded - retrying request")
                executeRequest(actualURL: actualURL, loadingRequest: loadingRequest, originalURL: originalURL, isRetry: true)
            } else {
                DebugLogger.error("Resource loader: Token refresh failed")
                loadingRequest.complete(with: NSError(
                    domain: Self.errorDomain,
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Authentication failed - please log in again"]
                ))
                removeTask(for: originalURL)
            }
        }
    }

    // MARK: - Content information

    /// Derive content-information from a response, parsing `Content-Range` for
    /// the total size when present (format `bytes 0-1/123456789`).
    static func contentInformation(from response: HTTPURLResponse) -> ResourceContentInformation {
        let contentRange = response.allHeaderFields["Content-Range"] as? String ??
            response.allHeaderFields["content-range"] as? String

        var contentLength = response.expectedContentLength
        if let contentRange {
            let components = contentRange.split(separator: "/")
            if components.count == 2, let totalSize = Int64(components[1]) {
                contentLength = totalSize
                DebugLogger.verbose("Resource loader: Total size from Content-Range: \(totalSize)")
            }
        }

        return ResourceContentInformation(
            contentType: response.mimeType,
            isByteRangeAccessSupported: true,
            contentLength: contentLength
        )
    }

    // MARK: - Task bookkeeping

    private func removeTask(for url: URL) {
        tasksLock.lock()
        loadingTasks.removeValue(forKey: url.absoluteString)
        tasksLock.unlock()
    }
}
