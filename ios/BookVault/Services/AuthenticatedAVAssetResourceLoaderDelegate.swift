//
//  AuthenticatedAVAssetResourceLoaderDelegate.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Handles AVPlayer authentication by intercepting resource loading requests
//

import AVFoundation
import Foundation

/// AVAssetResourceLoaderDelegate that adds Authorization header to AVPlayer requests
/// This is necessary because AVPlayer doesn't properly use headers from AVURLAsset options
///
/// Supports automatic token refresh on 401 responses to handle long playback sessions
/// where the access token may expire (default: 1 hour)
class AuthenticatedAVAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    /// Closure to get the current auth token (allows token to be refreshed externally)
    private let tokenProvider: () -> String?

    /// Closure to trigger token refresh, returns true if refresh succeeded
    private let tokenRefreshHandler: () async -> Bool

    private let session: URLSession
    private var loadingRequests: [String: URLSessionDataTask] = [:]

    /// Track if we're currently refreshing to avoid multiple concurrent refreshes
    private var isRefreshing = false
    private let refreshLock = NSLock()

    init(tokenProvider: @escaping () -> String?, tokenRefreshHandler: @escaping () async -> Bool) {
        self.tokenProvider = tokenProvider
        self.tokenRefreshHandler = tokenRefreshHandler

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)

        super.init()
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        DebugLogger.verbose("Resource loader: Request received")

        guard let url = loadingRequest.request.url else {
            DebugLogger.error("Resource loader: No URL in request")
            return false
        }

        DebugLogger.verbose("Resource loader: URL = \(url.absoluteString)")

        // Convert custom scheme back to http/https
        guard let actualURL = convertToActualURL(url) else {
            DebugLogger.error("Resource loader: Failed to convert URL")
            return false
        }

        DebugLogger.verbose("Resource loader: Actual URL = \(actualURL.absoluteString)")

        // Execute the request (with retry on 401)
        executeRequest(
            actualURL: actualURL,
            loadingRequest: loadingRequest,
            originalURL: url,
            isRetry: false
        )

        return true
    }

    /// Convert custom scheme URL back to actual http/https URL
    private func convertToActualURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Change custom scheme (bookvault://) back to http://
        if components.scheme == "bookvault" {
            components.scheme = "http"
        } else if components.scheme == "bookvaults" {
            components.scheme = "https"
        }

        return components.url
    }

    /// Create a URLRequest with current auth token and range headers
    private func createRequest(url: URL, loadingRequest: AVAssetResourceLoadingRequest) -> URLRequest? {
        guard let token = tokenProvider() else {
            DebugLogger.error("Resource loader: No authentication token available")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Handle range requests for seeking
        if let rangeHeader = loadingRequest.request.allHTTPHeaderFields?["Range"] {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        } else if let dataRequest = loadingRequest.dataRequest {
            // Construct range header from data request
            let offset = dataRequest.requestedOffset
            let length = dataRequest.requestedLength
            let rangeEnd = offset + Int64(length) - 1
            request.setValue("bytes=\(offset)-\(rangeEnd)", forHTTPHeaderField: "Range")
        }

        return request
    }

    /// Execute the request with optional retry on 401
    private func executeRequest(
        actualURL: URL,
        loadingRequest: AVAssetResourceLoadingRequest,
        originalURL: URL,
        isRetry: Bool
    ) {
        guard let request = createRequest(url: actualURL, loadingRequest: loadingRequest) else {
            let error = NSError(
                domain: "AuthenticatedAVAssetResourceLoaderDelegate",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No authentication token"]
            )
            loadingRequest.finishLoading(with: error)
            return
        }

        DebugLogger.verbose("Resource loader: Starting request\(isRetry ? " (retry)" : "")...")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                DebugLogger.error("Resource loader: Request failed", error: error)
                loadingRequest.finishLoading(with: error)
                self.loadingRequests.removeValue(forKey: originalURL.absoluteString)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DebugLogger.error("Resource loader: Invalid response type")
                loadingRequest.finishLoading(with: NSError(
                    domain: "AuthenticatedAVAssetResourceLoaderDelegate",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                ))
                self.loadingRequests.removeValue(forKey: originalURL.absoluteString)
                return
            }

            DebugLogger.verbose("Resource loader: Response status \(httpResponse.statusCode)")

            // Handle 401 - attempt token refresh and retry (only once)
            if httpResponse.statusCode == 401 && !isRetry {
                DebugLogger.auth("Resource loader: Received 401 - attempting token refresh...")
                self.handleUnauthorized(
                    actualURL: actualURL,
                    loadingRequest: loadingRequest,
                    originalURL: originalURL
                )
                return
            }

            // Handle other errors
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let error = NSError(
                    domain: "AuthenticatedAVAssetResourceLoaderDelegate",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                )
                DebugLogger.error("Resource loader: HTTP error \(httpResponse.statusCode)")
                loadingRequest.finishLoading(with: error)
                self.loadingRequests.removeValue(forKey: originalURL.absoluteString)
                return
            }

            // Success - process response
            loadingRequest.response = httpResponse
            self.fillContentInformation(loadingRequest: loadingRequest, response: httpResponse)

            if let data {
                loadingRequest.dataRequest?.respond(with: data)
            }

            loadingRequest.finishLoading()
            DebugLogger.verbose("Resource loader: Request completed successfully")

            self.loadingRequests.removeValue(forKey: originalURL.absoluteString)
        }

        loadingRequests[originalURL.absoluteString] = task
        task.resume()
    }

    /// Handle 401 by refreshing token and retrying
    private func handleUnauthorized(
        actualURL: URL,
        loadingRequest: AVAssetResourceLoadingRequest,
        originalURL: URL
    ) {
        // Use lock to prevent multiple concurrent refresh attempts
        refreshLock.lock()
        let shouldRefresh = !isRefreshing
        if shouldRefresh {
            isRefreshing = true
        }
        refreshLock.unlock()

        Task {
            var refreshSucceeded = false

            if shouldRefresh {
                // We're the one doing the refresh
                refreshSucceeded = await tokenRefreshHandler()

                refreshLock.lock()
                isRefreshing = false
                refreshLock.unlock()

                if refreshSucceeded {
                    DebugLogger.auth("Resource loader: Token refresh succeeded - retrying request")
                } else {
                    DebugLogger.error("Resource loader: Token refresh failed")
                }
            } else {
                // Another request is already refreshing, wait a bit and assume it succeeded
                // (the new token will be available via tokenProvider)
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                refreshSucceeded = tokenProvider() != nil
                DebugLogger.auth("Resource loader: Waited for concurrent refresh, token available: \(refreshSucceeded)")
            }

            if refreshSucceeded {
                // Retry the request with new token
                executeRequest(
                    actualURL: actualURL,
                    loadingRequest: loadingRequest,
                    originalURL: originalURL,
                    isRetry: true
                )
            } else {
                // Refresh failed - report error
                let error = NSError(
                    domain: "AuthenticatedAVAssetResourceLoaderDelegate",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Authentication failed - please log in again"]
                )
                loadingRequest.finishLoading(with: error)
                loadingRequests.removeValue(forKey: originalURL.absoluteString)
            }
        }
    }

    /// Fill content information from response headers
    private func fillContentInformation(loadingRequest: AVAssetResourceLoadingRequest, response: HTTPURLResponse) {
        guard let contentInfoRequest = loadingRequest.contentInformationRequest else { return }

        contentInfoRequest.contentType = response.mimeType
        contentInfoRequest.isByteRangeAccessSupported = true

        // Parse Content-Range header to get total file size
        // Format: "bytes 0-1/123456789"
        // Try both "Content-Range" and lowercase "content-range"
        let contentRange = response.allHeaderFields["Content-Range"] as? String ??
            response.allHeaderFields["content-range"] as? String

        if let contentRange {
            let components = contentRange.split(separator: "/")
            if components.count == 2, let totalSize = Int64(components[1]) {
                contentInfoRequest.contentLength = totalSize
                DebugLogger.verbose("Resource loader: Total size from Content-Range: \(totalSize)")
            } else {
                contentInfoRequest.contentLength = response.expectedContentLength
            }
        } else {
            contentInfoRequest.contentLength = response.expectedContentLength
        }
    }

    func resourceLoader(_: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = loadingRequest.request.url else { return }

        if let task = loadingRequests[url.absoluteString] {
            task.cancel()
            loadingRequests.removeValue(forKey: url.absoluteString)
        }
    }
}
