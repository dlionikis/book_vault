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
protocol ResourceLoadingRequesting: AnyObject {
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
final class AuthenticatedResourceLoader {
    private let tokenProvider: () -> String?
    private let tokenRefreshHandler: () async -> Bool
    private let session: URLSession

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
        tokenProvider: @escaping () -> String?,
        tokenRefreshHandler: @escaping () async -> Bool,
        session: URLSession,
        refreshCoordinator: TokenRefreshCoordinator = TokenRefreshCoordinator()
    ) {
        self.tokenProvider = tokenProvider
        self.tokenRefreshHandler = tokenRefreshHandler
        self.session = session
        self.refreshCoordinator = refreshCoordinator
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

        executeRequest(actualURL: actualURL, loadingRequest: request, originalURL: url, isRetry: false)
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
    func makeAuthenticatedRequest(url: URL, for loadingRequest: ResourceLoadingRequesting) -> URLRequest? {
        guard let token = tokenProvider() else {
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

    private func executeRequest(
        actualURL: URL,
        loadingRequest: ResourceLoadingRequesting,
        originalURL: URL,
        isRetry: Bool
    ) {
        guard let request = makeAuthenticatedRequest(url: actualURL, for: loadingRequest) else {
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
                self.handleUnauthorized(actualURL: actualURL, loadingRequest: loadingRequest, originalURL: originalURL)
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
        originalURL: URL
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
            let refreshSucceeded = await refreshCoordinator.refresh(using: handler)

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
