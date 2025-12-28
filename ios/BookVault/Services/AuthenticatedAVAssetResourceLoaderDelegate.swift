//
//  AuthenticatedAVAssetResourceLoaderDelegate.swift
//  BookVault
//
//  Created by Claude Code on 12/27/25.
//  Handles AVPlayer authentication by intercepting resource loading requests
//

import Foundation
import AVFoundation

/// AVAssetResourceLoaderDelegate that adds Authorization header to AVPlayer requests
/// This is necessary because AVPlayer doesn't properly use headers from AVURLAsset options
class AuthenticatedAVAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let authToken: String
    private let session: URLSession
    private var loadingRequests: [String: URLSessionDataTask] = [:]

    init(authToken: String) {
        self.authToken = authToken

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)

        super.init()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {

        #if DEBUG
        print("🔄 Resource loader: Request received")
        #endif

        guard let url = loadingRequest.request.url else {
            #if DEBUG
            print("❌ Resource loader: No URL in request")
            #endif
            return false
        }

        #if DEBUG
        print("🔄 Resource loader: URL = \(url.absoluteString)")
        #endif

        // Convert custom scheme back to http/https
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            #if DEBUG
            print("❌ Resource loader: Failed to create URL components")
            #endif
            return false
        }

        // Change custom scheme (bookvault://) back to http://
        if components.scheme == "bookvault" {
            components.scheme = "http"
        } else if components.scheme == "bookvaults" {
            components.scheme = "https"
        }

        guard let actualURL = components.url else {
            #if DEBUG
            print("❌ Resource loader: Failed to convert URL")
            #endif
            return false
        }

        #if DEBUG
        print("🔄 Resource loader: Actual URL = \(actualURL.absoluteString)")
        #endif

        // Create request with auth header
        var request = URLRequest(url: actualURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

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

        #if DEBUG
        print("🔄 Resource loader: Starting request...")
        #endif

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                #if DEBUG
                print("❌ Resource loader: Request failed - \(error.localizedDescription)")
                #endif
                loadingRequest.finishLoading(with: error)
                return
            }

            if let response = response as? HTTPURLResponse {
                #if DEBUG
                print("🔄 Resource loader: Response status \(response.statusCode)")
                #endif
                loadingRequest.response = response

                // Fill content information
                if let contentInfoRequest = loadingRequest.contentInformationRequest {
                    contentInfoRequest.contentType = response.mimeType
                    contentInfoRequest.isByteRangeAccessSupported = true

                    // Parse Content-Range header to get total file size
                    // Format: "bytes 0-1/123456789"
                    // Try both "Content-Range" and lowercase "content-range"
                    let contentRange = response.allHeaderFields["Content-Range"] as? String ??
                                     response.allHeaderFields["content-range"] as? String

                    if let contentRange = contentRange {
                        let components = contentRange.split(separator: "/")
                        if components.count == 2, let totalSize = Int64(components[1]) {
                            contentInfoRequest.contentLength = totalSize
                            #if DEBUG
                            print("🔄 Resource loader: Total size from Content-Range: \(totalSize)")
                            #endif
                        } else {
                            contentInfoRequest.contentLength = response.expectedContentLength
                        }
                    } else {
                        contentInfoRequest.contentLength = response.expectedContentLength
                    }
                }
            }

            if let data = data {
                loadingRequest.dataRequest?.respond(with: data)
            }

            loadingRequest.finishLoading()
            #if DEBUG
            print("✅ Resource loader: Request completed successfully")
            #endif

            // Cleanup
            self.loadingRequests.removeValue(forKey: url.absoluteString)
        }

        loadingRequests[url.absoluteString] = task
        task.resume()

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = loadingRequest.request.url else { return }

        if let task = loadingRequests[url.absoluteString] {
            task.cancel()
            loadingRequests.removeValue(forKey: url.absoluteString)
        }
    }
}
