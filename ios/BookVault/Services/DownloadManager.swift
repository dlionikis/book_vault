//
//  DownloadManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 7: Offline Downloads
//

import Foundation
import UIKit

/// Download state enumeration
enum DownloadState: Equatable {
    case notDownloaded
    case waiting
    case downloading(progress: Double)
    case paused(progress: Double)
    case completed
    case failed(error: String)
}

/// Active download tracking
struct ActiveDownload: Identifiable {
    let id: String  // bookId
    let book: Book
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var state: DownloadState
    var task: URLSessionDownloadTask?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }

    var formattedProgress: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }
}

/// Download error types
enum DownloadError: LocalizedError {
    case networkError(String)
    case insufficientStorage
    case rateLimitExceeded
    case urlExpired
    case fileCorruption
    case unauthorized
    case notEligible
    case wifiRequired
    case cancelled

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .insufficientStorage:
            return "Not enough storage space"
        case .rateLimitExceeded:
            return "Daily download limit reached (50/day)"
        case .urlExpired:
            return "Download URL expired"
        case .fileCorruption:
            return "Downloaded file is corrupted"
        case .unauthorized:
            return "Not authorized to download"
        case .notEligible:
            return "Not eligible to download this book"
        case .wifiRequired:
            return "WiFi required for downloads"
        case .cancelled:
            return "Download was cancelled"
        }
    }
}

/// Manages audiobook downloads with background support
@MainActor
class DownloadManager: NSObject, ObservableObject, DownloadManaging {
    static let shared = DownloadManager()

    // MARK: - Published Properties

    @Published var activeDownloads: [String: ActiveDownload] = [:]
    @Published var error: DownloadError?

    // MARK: - Dependencies (DI for testing)

    private let apiClient: APIClientProtocol
    private let storageManager: StorageManaging
    private let networkMonitor: NetworkMonitoring

    // Force logout handler (enables DI for testing)
    var forceLogoutHandler: () -> Void = {
        Task { @MainActor in
            AuthManager.shared.forceLogout()
        }
    }

    private var backgroundSession: URLSession!
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var pendingBooks: [String: Book] = [:]

    // Thread-safe storage for file extensions (accessed from nonisolated delegate)
    // Using NSLock for thread safety since delegate callbacks are on background queue
    // nonisolated(unsafe) is required because we need to access from both main actor and delegate callbacks
    private let fileExtensionsLock = NSLock()
    private nonisolated(unsafe) var _pendingFileExtensions: [String: String] = [:]  // bookId -> file extension

    // These methods are explicitly nonisolated because they use thread-safe locking
    // and need to be called from both main actor context and URLSession delegate callbacks
    private nonisolated func setFileExtension(_ ext: String, for bookId: String) {
        fileExtensionsLock.lock()
        defer { fileExtensionsLock.unlock() }
        _pendingFileExtensions[bookId] = ext
    }

    private nonisolated func getFileExtension(for bookId: String) -> String {
        fileExtensionsLock.lock()
        defer { fileExtensionsLock.unlock() }
        return _pendingFileExtensions[bookId] ?? "mp3"
    }

    private nonisolated func removeFileExtension(for bookId: String) {
        fileExtensionsLock.lock()
        defer { fileExtensionsLock.unlock() }
        _pendingFileExtensions.removeValue(forKey: bookId)
    }

    // Background session identifier
    private let backgroundSessionIdentifier: String

    // MARK: - Initialization

    // Production singleton init
    private convenience override init() {
        self.init(
            apiClient: APIClient.shared,
            storageManager: StorageManager.shared,
            networkMonitor: NetworkMonitor.shared,
            sessionIdentifier: "com.bookvault.downloads"
        )
    }

    // Testable initializer
    init(
        apiClient: APIClientProtocol,
        storageManager: StorageManaging,
        networkMonitor: NetworkMonitoring,
        sessionIdentifier: String = "com.bookvault.downloads.test",
        session: URLSession? = nil
    ) {
        self.apiClient = apiClient
        self.storageManager = storageManager
        self.networkMonitor = networkMonitor
        self.backgroundSessionIdentifier = sessionIdentifier
        super.init()

        if let session = session {
            // Use injected session (for testing)
            self.backgroundSession = session
        } else {
            // Create background session
            setupBackgroundSession()
        }
    }

    private func setupBackgroundSession() {
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        config.isDiscretionary = false  // Don't delay downloads
        config.sessionSendsLaunchEvents = true  // Wake app when download completes
        config.allowsCellularAccess = true  // WiFi-only is checked separately

        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        DebugLogger.download("Background session initialized")
    }

    // MARK: - Public API

    /// Get download state for a book
    func downloadState(for bookId: String) -> DownloadState {
        // Check if actively downloading
        if let active = activeDownloads[bookId] {
            return active.state
        }

        // Check if already downloaded
        if storageManager.isBookDownloaded(bookId: bookId) {
            return .completed
        }

        return .notDownloaded
    }

    /// Check if a book is currently downloading
    func isDownloading(bookId: String) -> Bool {
        guard let active = activeDownloads[bookId] else { return false }
        switch active.state {
        case .waiting, .downloading:
            return true
        default:
            return false
        }
    }

    /// Start downloading a book
    func startDownload(book: Book) async throws {
        let bookId = book.id.uuidString

        // Check if already downloading
        if isDownloading(bookId: bookId) {
            DebugLogger.download("Already downloading: \(book.title)")
            return
        }

        // Check if already downloaded
        if storageManager.isBookDownloaded(bookId: bookId) {
            DebugLogger.download("Already downloaded: \(book.title)")
            return
        }

        // Check network eligibility
        if !networkMonitor.canDownload {
            throw DownloadError.wifiRequired
        }

        DebugLogger.download("Starting download: \(book.title)")

        // Create initial download state
        let download = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 0,
            totalBytes: 0,
            state: .waiting,
            task: nil
        )
        activeDownloads[bookId] = download
        pendingBooks[bookId] = book

        // Extract file extension from audioUrl (e.g., ".mp3" or ".m4a")
        // This must use thread-safe method since delegate callbacks access it
        if let audioUrl = book.audioUrl, let url = URL(string: audioUrl) {
            let ext = url.pathExtension.lowercased()
            let fileExt = ext.isEmpty ? "mp3" : ext
            setFileExtension(fileExt, for: bookId)
            DebugLogger.download("File extension for \(book.title): \(fileExt)")
        } else {
            setFileExtension("mp3", for: bookId)  // Default to mp3
        }

        do {
            // Check eligibility with backend
            let eligible = try await checkEligibility(bookId: bookId)
            guard eligible else {
                activeDownloads.removeValue(forKey: bookId)
                throw DownloadError.notEligible
            }

            // Get pre-signed download URL
            let downloadInfo = try await generateDownloadUrl(bookId: bookId)

            // Check storage space
            guard storageManager.canDownload(fileSize: Int64(downloadInfo.fileSize)) else {
                activeDownloads.removeValue(forKey: bookId)
                throw DownloadError.insufficientStorage
            }

            // Update download with total bytes
            activeDownloads[bookId]?.totalBytes = Int64(downloadInfo.fileSize)
            activeDownloads[bookId]?.state = .downloading(progress: 0)

            // Start the download
            guard let url = URL(string: downloadInfo.downloadUrl) else {
                activeDownloads.removeValue(forKey: bookId)
                throw DownloadError.networkError("Invalid download URL")
            }

            // Create download task - use URLRequest with auth for API URLs, plain URL for S3
            let task: URLSessionDownloadTask
            if url.path.hasPrefix("/api/") || url.absoluteString.contains("/api/") {
                // Local API URL - needs authentication header
                var request = URLRequest(url: url)
                if let token = apiClient.accessToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                task = backgroundSession.downloadTask(with: request)
                DebugLogger.download("Using authenticated request for API download")
            } else {
                // S3 pre-signed URL - auth is in the URL itself
                task = backgroundSession.downloadTask(with: url)
                DebugLogger.download("Using pre-signed URL for S3 download")
            }

            task.taskDescription = bookId  // Store bookId for delegate callbacks
            downloadTasks[bookId] = task
            activeDownloads[bookId]?.task = task

            task.resume()

            DebugLogger.download("Download started: \(book.title) (\(StorageManager.formatFileSize(Int64(downloadInfo.fileSize))))")

        } catch {
            activeDownloads.removeValue(forKey: bookId)
            pendingBooks.removeValue(forKey: bookId)

            if let downloadError = error as? DownloadError {
                throw downloadError
            }
            throw DownloadError.networkError(error.localizedDescription)
        }
    }

    /// Cancel a download
    func cancelDownload(bookId: String) {
        guard let download = activeDownloads[bookId] else { return }

        download.task?.cancel()
        downloadTasks.removeValue(forKey: bookId)
        activeDownloads.removeValue(forKey: bookId)
        pendingBooks.removeValue(forKey: bookId)
        removeFileExtension(for: bookId)

        DebugLogger.download("Download cancelled: \(bookId)")
    }

    /// Pause a download
    func pauseDownload(bookId: String) {
        guard let download = activeDownloads[bookId],
              let task = download.task else { return }

        task.cancel(byProducingResumeData: { _ in
            // Resume data is automatically saved by URLSession
        })

        activeDownloads[bookId]?.state = .paused(progress: download.progress)
        DebugLogger.download("Download paused: \(bookId)")
    }

    /// Resume a paused download
    func resumeDownload(book: Book) async throws {
        // For now, just restart the download
        // In future, could use resume data
        try await startDownload(book: book)
    }

    /// Delete a downloaded book
    func deleteDownload(bookId: String) throws {
        try storageManager.deleteDownload(bookId: bookId)
        DebugLogger.download("Download deleted: \(bookId)")
    }

    // MARK: - API Calls

    private func checkEligibility(bookId: String) async throws -> Bool {
        let request = try createAuthenticatedRequest(
            path: "/api/downloads/\(bookId)/check",
            method: "GET"
        )

        DebugLogger.download("Checking eligibility: \(request.url?.absoluteString ?? "nil")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError("Invalid response")
        }

        DebugLogger.download("Eligibility response: HTTP \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(CheckDownloadEligibility200Response.self, from: data)
            DebugLogger.download("Eligibility result: \(result.eligible)")
            return result.eligible
        case 401:
            // Force logout via handler (enables DI for testing)
            forceLogoutHandler()
            throw DownloadError.unauthorized
        case 429:
            throw DownloadError.rateLimitExceeded
        default:
            // Log response body for debugging
            if let responseBody = String(data: data, encoding: .utf8) {
                DebugLogger.error("Eligibility check failed: \(responseBody)")
            }
            throw DownloadError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    private func generateDownloadUrl(bookId: String) async throws -> GenerateDownloadUrl200Response {
        var request = try createAuthenticatedRequest(
            path: "/api/downloads/\(bookId)",
            method: "POST"
        )

        // Add device ID to request body
        let deviceId = UIDevice.current.identifierForVendor?.uuidString
        let body = GenerateDownloadUrlRequest(deviceId: deviceId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GenerateDownloadUrl200Response.self, from: data)
        case 401:
            // Force logout via handler (enables DI for testing)
            forceLogoutHandler()
            throw DownloadError.unauthorized
        case 429:
            throw DownloadError.rateLimitExceeded
        case 501:
            throw DownloadError.networkError("Downloads require S3 configuration")
        default:
            throw DownloadError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    private func createAuthenticatedRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: apiClient.baseURL) else {
            throw DownloadError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = apiClient.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Background Session Handling

    /// Handle background session events (call from AppDelegate/SceneDelegate)
    func handleBackgroundSessionEvents(completionHandler: @escaping () -> Void) {
        // Store completion handler to call when all tasks complete
        DebugLogger.download("Handling background session events")
        completionHandler()
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let bookId = downloadTask.taskDescription else {
            DebugLogger.error("Download completed but no bookId found")
            return
        }

        // CRITICAL: The temp file at `location` is only valid during this callback!
        // We must move it synchronously before returning, then update UI on main actor.
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audiobooksDir = documentsURL.appendingPathComponent("downloads/audiobooks")

        // Get the correct file extension (thread-safe access)
        let fileExtension = getFileExtension(for: bookId)
        let destinationPath = audiobooksDir.appendingPathComponent("\(bookId).\(fileExtension)")

        do {
            // Ensure directory exists
            if !fileManager.fileExists(atPath: audiobooksDir.path) {
                try fileManager.createDirectory(at: audiobooksDir, withIntermediateDirectories: true)
                DebugLogger.storage("Created audiobooks directory from delegate")
            }

            // Remove existing file if present
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }

            // Move temp file to permanent location (must happen synchronously!)
            try fileManager.moveItem(at: location, to: destinationPath)

            DebugLogger.storage("Moved download to: \(destinationPath.lastPathComponent)")

            // Now update UI and metadata on main actor
            Task { @MainActor in
                await self.handleDownloadComplete(bookId: bookId, savedPath: destinationPath)
            }
        } catch {
            DebugLogger.error("Failed to move downloaded file", error: error)
            Task { @MainActor in
                self.activeDownloads[bookId]?.state = .failed(error: error.localizedDescription)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let bookId = downloadTask.taskDescription else { return }

        Task { @MainActor in
            updateProgress(
                bookId: bookId,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let bookId = downloadTask.taskDescription else { return }

        if let error = error {
            Task { @MainActor in
                handleDownloadError(bookId: bookId, error: error)
            }
        }
    }

    // MARK: - Private Handlers

    /// Called after file has been successfully moved to permanent location
    private func handleDownloadComplete(bookId: String, savedPath: URL) async {
        guard let book = pendingBooks[bookId] else {
            DebugLogger.error("Download complete but book not found: \(bookId)")
            return
        }

        // Get file extension (thread-safe) before cleaning up
        let fileExtension = getFileExtension(for: bookId)

        // Get file size using explicit extension (metadata not saved yet)
        let fileSize = storageManager.downloadedFileSize(for: bookId, extension: fileExtension) ?? 0

        // Update metadata with file extension
        storageManager.addToMetadata(book: book, fileSize: fileSize, fileExtension: fileExtension)

        // Update state
        activeDownloads[bookId]?.state = .completed
        downloadTasks.removeValue(forKey: bookId)
        pendingBooks.removeValue(forKey: bookId)
        removeFileExtension(for: bookId)  // Clean up thread-safe storage

        // Remove from active downloads after short delay (to show completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.activeDownloads.removeValue(forKey: bookId)
        }

        DebugLogger.success("Download complete: \(book.title) saved to \(savedPath.lastPathComponent)")
    }

    private func updateProgress(bookId: String, bytesWritten: Int64, totalBytes: Int64) {
        guard var download = activeDownloads[bookId] else { return }

        download.bytesDownloaded = bytesWritten
        if totalBytes > 0 {
            download.totalBytes = totalBytes
        }

        let progress = download.progress
        download.state = .downloading(progress: progress)

        activeDownloads[bookId] = download
    }

    private func handleDownloadError(bookId: String, error: Error) {
        let nsError = error as NSError

        // Check if cancelled
        if nsError.code == NSURLErrorCancelled {
            activeDownloads.removeValue(forKey: bookId)
            return
        }

        // Update state with error
        let errorMessage = error.localizedDescription
        activeDownloads[bookId]?.state = .failed(error: errorMessage)

        DebugLogger.error("Download failed: \(bookId)", error: error)
    }
}

// MARK: - DebugLogger Extension for Downloads

extension DebugLogger {
    static func download(_ message: String) {
        log(message, category: .info)  // Use info category for download operations
    }
}
