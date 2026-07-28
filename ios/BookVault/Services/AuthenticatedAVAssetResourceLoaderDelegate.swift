//
//  AuthenticatedAVAssetResourceLoaderDelegate.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Handles AVPlayer authentication by intercepting resource loading requests
//

import AVFoundation
import Foundation

/// AVAssetResourceLoaderDelegate that adds Authorization header to AVPlayer requests.
/// This is necessary because AVPlayer doesn't properly use headers from AVURLAsset options.
///
/// Supports automatic token refresh on 401 responses to handle long playback sessions
/// where the access token may expire (default: 1 hour).
///
/// This type is a thin AVFoundation shim over `AuthenticatedResourceLoader`, which
/// holds all the tested behavior. `AVAssetResourceLoadingRequest` has no public
/// initializer, so the shim can't be unit-tested directly; the core loader is
/// tested against a mock `ResourceLoadingRequesting` conformance instead.
class AuthenticatedAVAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let loader: AuthenticatedResourceLoader

    /// - Parameter refreshCoordinator: the app-wide refresh coordinator. A new
    ///   delegate is built for each playback, so this must be passed in rather
    ///   than created per-instance — otherwise the streaming path would refresh
    ///   independently of the JSON API path, which is the bug this shares state
    ///   to avoid.
    init(
        tokenProvider: @escaping () -> String?,
        tokenRefreshHandler: @escaping () async -> Bool,
        refreshCoordinator: TokenRefreshCoordinator
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)

        loader = AuthenticatedResourceLoader(
            tokenProvider: tokenProvider,
            tokenRefreshHandler: tokenRefreshHandler,
            session: session,
            refreshCoordinator: refreshCoordinator
        )

        super.init()
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        DebugLogger.verbose("Resource loader: Request received")
        return loader.startLoading(loadingRequest)
    }

    func resourceLoader(_: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = loadingRequest.request.url else { return }
        loader.cancelLoading(for: url)
    }
}

// MARK: - AVAssetResourceLoadingRequest + ResourceLoadingRequesting

/// Adapts the concrete AVFoundation loading request to the testable protocol.
/// Declarative glue only — the behavior it forwards into is covered by
/// `AuthenticatedResourceLoaderTests`.
extension AVAssetResourceLoadingRequest: ResourceLoadingRequesting {
    var requestURL: URL? { request.url }

    var explicitRangeHeader: String? { request.allHTTPHeaderFields?["Range"] }

    var requestedByteRange: (offset: Int64, length: Int)? {
        guard let dataRequest else { return nil }
        return (offset: dataRequest.requestedOffset, length: dataRequest.requestedLength)
    }

    func acceptResponse(_ httpResponse: HTTPURLResponse, info: ResourceContentInformation) {
        response = httpResponse
        guard let contentInfoRequest = contentInformationRequest else { return }
        contentInfoRequest.contentType = info.contentType
        contentInfoRequest.isByteRangeAccessSupported = info.isByteRangeAccessSupported
        contentInfoRequest.contentLength = info.contentLength
    }

    func respondWithData(_ data: Data) {
        dataRequest?.respond(with: data)
    }

    func complete() {
        finishLoading()
    }

    func complete(with error: Error) {
        finishLoading(with: error)
    }
}
