//
//  DownloadManager.swift
//  BookVault
//
//  Created by Claude Code on 12/29/25.
//  Phase 7: Offline Downloads
//

import Foundation
import UIKit

// MARK: - DownloadState

/// Download state enumeration
enum DownloadState: Equatable {
    case notDownloaded
    case waiting
    case downloading(progress: Double)
    case backgroundDownloading(lastProgress: Double) // App was backgrounded during download
    case paused(progress: Double)
    case completed
    case failed(error: String)
}

// MARK: - ActiveDownload

/// Active download tracking
struct ActiveDownload: Identifiable {
    let id: String // bookId
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

// MARK: - DownloadError

/// Download error types
enum DownloadError: LocalizedError, Equatable {
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
        case let .networkError(message):
            "Network error: \(message)"
        case .insufficientStorage:
            "Not enough storage space"
        case .rateLimitExceeded:
            "Daily download limit reached (50/day)"
        case .urlExpired:
            "Download URL expired"
        case .fileCorruption:
            "Downloaded file is corrupted"
        case .unauthorized:
            "Not authorized to download"
        case .notEligible:
            "Not eligible to download this book"
        case .wifiRequired:
            "WiFi required for downloads"
        case .cancelled:
            "Download was cancelled"
        }
    }
}

// MARK: - FileExtensionStorage

/// Thread-safe storage for file extensions
/// Used to pass file extension info from main actor to URLSession delegate callbacks
/// Encapsulates thread-safety with NSLock for clean cross-actor access
final class FileExtensionStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func set(_ ext: String, for bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[bookId] = ext
    }

    func get(for bookId: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return storage[bookId] ?? "mp3"
    }

    func remove(for bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: bookId)
    }
}

// MARK: - PendingDownloadInfo

/// Persisted info about downloads in progress
/// Used to restore UI state after app termination and relaunch
struct PendingDownloadInfo: Codable {
    let bookId: String
    let bookTitle: String
    let bookAuthor: String
    let fileExtension: String
    var totalBytes: Int64
    var bytesDownloaded: Int64
    let startedAt: Date
}

// MARK: - DownloadManager

/// Manages audiobook downloads with background support
@MainActor
class DownloadManager: NSObject, ObservableObject, DownloadManaging {
    static let shared = DownloadManager()

    // MARK: - Published Properties

    @Published var activeDownloads: [String: ActiveDownload] = [:]
    @Published var error: DownloadError?

    // MARK: - Dependencies (DI for testing)

    private let apiClient: any APIClientProtocol
    private let storageManager: any StorageManaging
    private let networkMonitor: any NetworkMonitoring

    private var downloadSession: URLSession!
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var pendingBooks: [String: Book] = [:]

    // Thread-safe storage for file extensions (accessed from URLSession delegate callbacks)
    private let fileExtensionStorage = FileExtensionStorage()

    // Background session completion handler (called by AppDelegate)
    private var backgroundCompletionHandler: (() -> Void)?

    // Session identifier for background URLSession
    private let sessionIdentifier: String

    // UserDefaults key for persisting pending downloads
    private let pendingDownloadsKey = "com.bookvault.pendingDownloads"

    // UserDefaults key for persisting resume data
    private let resumeDataKeyPrefix = "com.bookvault.resumeData."

    // UserDefaults instance (injectable for testing)
    private let userDefaults: UserDefaults

    // MARK: - Initialization

    // Production singleton init
    override private convenience init() {
        self.init(
            apiClient: APIClient.shared,
            storageManager: StorageManager.shared,
            networkMonitor: NetworkMonitor.shared,
            sessionIdentifier: "com.bookvault.downloads",
            userDefaults: .standard
        )
    }

    // Testable initializer
    init(
        apiClient: any APIClientProtocol,
        storageManager: any StorageManaging,
        networkMonitor: any NetworkMonitoring,
        sessionIdentifier: String = "com.bookvault.downloads.test",
        userDefaults: UserDefaults = .standard,
        session: URLSession? = nil
    ) {
        self.apiClient = apiClient
        self.storageManager = storageManager
        self.networkMonitor = networkMonitor
        self.sessionIdentifier = sessionIdentifier
        self.userDefaults = userDefaults
        super.init()

        if let session {
            // Use injected session (for testing)
            self.downloadSession = session
        } else {
            // Create background session for downloads that survive app termination
            setupDownloadSession()
        }

        // Restore any pending downloads from previous app session
        restorePendingDownloads()

        // Register for app lifecycle notifications
        setupLifecycleNotifications()
    }

    /// Register for app lifecycle notifications to update UI when returning to foreground
    private func setupLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applicationWillEnterForeground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applicationDidEnterBackground()
            }
        }
    }

    /// Called when app is about to enter foreground - refresh download states
    private func applicationWillEnterForeground() {
        guard !activeDownloads.isEmpty else { return }

        DebugLogger.download("App entering foreground, refreshing download states")

        // Query background session for current task states
        downloadSession.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                self?.updateUIFromBackgroundTasks(tasks)
            }
        }
    }

    /// Called when app enters background - mark active downloads as background downloading
    private func applicationDidEnterBackground() {
        for (bookId, download) in activeDownloads {
            if case let .downloading(progress) = download.state {
                activeDownloads[bookId]?.state = .backgroundDownloading(lastProgress: progress)
                DebugLogger.download("Marked \(bookId) as background downloading at \(Int(progress * 100))%")
            }
        }
    }

    /// Update UI state from actual background session tasks
    private func updateUIFromBackgroundTasks(_ tasks: [URLSessionTask]) {
        let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }

        DebugLogger.download("Updating UI from \(downloadTasks.count) background tasks")

        for task in downloadTasks {
            guard let bookId = task.taskDescription else { continue }

            // Calculate current progress from task
            let totalBytes = task.countOfBytesExpectedToReceive
            let bytesReceived = task.countOfBytesReceived

            if totalBytes > 0, var download = activeDownloads[bookId] {
                let progress = Double(bytesReceived) / Double(totalBytes)
                download.bytesDownloaded = bytesReceived
                download.totalBytes = totalBytes
                download.state = .downloading(progress: progress)
                download.task = task
                activeDownloads[bookId] = download

                DebugLogger.download("Updated \(bookId): \(Int(progress * 100))%")
            }
        }

        // Check for completed downloads that finished while backgrounded
        let taskBookIds = Set(downloadTasks.compactMap { $0.taskDescription })
        for (bookId, download) in activeDownloads {
            if case .backgroundDownloading = download.state,
               !taskBookIds.contains(bookId) {
                // Task is gone - check if completed
                if storageManager.isBookDownloaded(bookId: bookId) {
                    activeDownloads[bookId]?.state = .completed
                    removePendingDownloadInfo(bookId: bookId)
                    DebugLogger.download("Download completed while backgrounded: \(bookId)")

                    // Remove from active after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.activeDownloads.removeValue(forKey: bookId)
                    }
                }
            }
        }
    }

    private func setupDownloadSession() {
        // Use background configuration so downloads continue when app is backgrounded/terminated
        // The system daemon (nsurlsessiond) handles the actual transfer
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false // Start immediately, don't defer to optimal conditions
        config.sessionSendsLaunchEvents = true // Relaunch app when downloads complete
        config.allowsCellularAccess = true // WiFi-only is checked separately via NetworkMonitor
        config.timeoutIntervalForResource = 3600 // 1 hour timeout for large files
        config.waitsForConnectivity = true // Wait for network if unavailable

        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        DebugLogger.download("Download session initialized (background mode, id: \(sessionIdentifier))")
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
        case .waiting,
             .downloading:
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
        let fileExt: String
        if let audioUrl = book.audioUrl, let url = URL(string: audioUrl) {
            let ext = url.pathExtension.lowercased()
            fileExt = ext.isEmpty ? "mp3" : ext
            DebugLogger.download("File extension for \(book.title): \(fileExt)")
        } else {
            fileExt = "mp3" // Default to mp3
        }
        fileExtensionStorage.set(fileExt, for: bookId)

        // Persist pending download info for app restart recovery
        savePendingDownloadInfo(bookId: bookId, book: book, fileExtension: fileExt)

        do {
            // Check eligibility with backend
            let eligible = try await checkEligibility(bookId: book.id)
            guard eligible else {
                activeDownloads.removeValue(forKey: bookId)
                removePendingDownloadInfo(bookId: bookId)
                throw DownloadError.notEligible
            }

            // Get pre-signed download URL
            let downloadInfo = try await generateDownloadUrl(bookId: book.id)

            // Check storage space
            guard storageManager.canDownload(fileSize: Int64(downloadInfo.fileSize)) else {
                activeDownloads.removeValue(forKey: bookId)
                removePendingDownloadInfo(bookId: bookId)
                throw DownloadError.insufficientStorage
            }

            // Update download with total bytes
            activeDownloads[bookId]?.totalBytes = Int64(downloadInfo.fileSize)
            activeDownloads[bookId]?.state = .downloading(progress: 0)

            // Start the download
            guard let url = URL(string: downloadInfo.downloadUrl) else {
                activeDownloads.removeValue(forKey: bookId)
                removePendingDownloadInfo(bookId: bookId)
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
                task = downloadSession.downloadTask(with: request)
                DebugLogger.download("Using authenticated request for API download")
            } else {
                // S3 pre-signed URL - auth is in the URL itself
                task = downloadSession.downloadTask(with: url)
                DebugLogger.download("Using pre-signed URL for S3 download")
            }

            task.taskDescription = bookId // Store bookId for delegate callbacks
            downloadTasks[bookId] = task
            activeDownloads[bookId]?.task = task

            task.resume()

            DebugLogger
                .download(
                    "Download started: \(book.title) (\(StorageManager.formatFileSize(Int64(downloadInfo.fileSize))))"
                )
        } catch {
            activeDownloads.removeValue(forKey: bookId)
            pendingBooks.removeValue(forKey: bookId)
            removePendingDownloadInfo(bookId: bookId)

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
        fileExtensionStorage.remove(for: bookId)
        removePendingDownloadInfo(bookId: bookId)

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
    ///
    /// If resume data is available from a previous interrupted download,
    /// this will use it to continue from where it left off. Otherwise,
    /// it restarts the download from the beginning.
    func resumeDownload(book: Book) async throws {
        let bookId = book.id.uuidString

        // Check if we have resume data
        if let resumeData = loadResumeData(bookId: bookId) {
            DebugLogger.download("Resuming download with saved resume data: \(book.title)")

            // Create task from resume data
            let task = downloadSession.downloadTask(withResumeData: resumeData)
            task.taskDescription = bookId

            // Update tracking
            downloadTasks[bookId] = task
            if var download = activeDownloads[bookId] {
                download.task = task
                download.state = .downloading(progress: download.progress)
                activeDownloads[bookId] = download
            }

            // Clear resume data since we're using it
            clearResumeData(bookId: bookId)

            task.resume()
            return
        }

        // No resume data - restart from beginning
        try await startDownload(book: book)
    }

    /// Delete a downloaded book
    func deleteDownload(bookId: String) throws {
        try storageManager.deleteDownload(bookId: bookId)
        DebugLogger.download("Download deleted: \(bookId)")
    }

    /// Get storage statistics for downloaded books
    /// - Returns: Tuple of (count, size in bytes)
    func getStorageStats() -> (count: Int, size: Int64) {
        return (storageManager.downloads.count, storageManager.totalSize)
    }

    // MARK: - API Calls

    private func checkEligibility(bookId: UUID) async throws -> Bool {
        DebugLogger.download("Checking eligibility for book: \(bookId.uuidString)")

        do {
            let result = try await apiClient.checkDownloadEligibility(bookId: bookId)
            DebugLogger.download("Eligibility result: \(result.eligible)")
            return result.eligible
        } catch {
            DebugLogger.error("Eligibility check failed", error: error)
            throw Self.mapToDownloadError(error)
        }
    }

    private func generateDownloadUrl(bookId: UUID) async throws -> GenerateDownloadUrl200Response {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString

        do {
            return try await apiClient.generateDownloadUrl(bookId: bookId, deviceId: deviceId)
        } catch {
            DebugLogger.error("Download URL generation failed", error: error)
            throw Self.mapToDownloadError(error)
        }
    }

    /// Map APIClient errors to download-specific error cases
    private static func mapToDownloadError(_ error: Error) -> DownloadError {
        guard let apiError = error as? APIError else {
            return .networkError(error.localizedDescription)
        }

        switch apiError {
        case .unauthorized:
            // APIClient already attempted token refresh and forced logout if needed
            return .unauthorized
        case .serverError(429, _):
            return .rateLimitExceeded
        case .serverError(501, _):
            return .networkError("Downloads require S3 configuration")
        default:
            return .networkError(apiError.localizedDescription)
        }
    }

    // MARK: - Pending Downloads Persistence

    /// Load pending download info from UserDefaults
    private func loadPendingDownloadsInfo() -> [String: PendingDownloadInfo] {
        guard let data = userDefaults.data(forKey: pendingDownloadsKey) else {
            return [:]
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([String: PendingDownloadInfo].self, from: data)
        } catch {
            DebugLogger.error("Failed to decode pending downloads", error: error)
            return [:]
        }
    }

    /// Save pending download info to UserDefaults
    private func savePendingDownloadsInfo(_ info: [String: PendingDownloadInfo]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(info)
            userDefaults.set(data, forKey: pendingDownloadsKey)
            DebugLogger.download("Saved \(info.count) pending downloads to UserDefaults")
        } catch {
            DebugLogger.error("Failed to encode pending downloads", error: error)
        }
    }

    /// Save info for a new pending download
    private func savePendingDownloadInfo(bookId: String, book: Book, fileExtension: String) {
        var pending = loadPendingDownloadsInfo()
        // Extract first author name for display
        let authorName = book.authors.first?.name ?? "Unknown Author"
        pending[bookId] = PendingDownloadInfo(
            bookId: bookId,
            bookTitle: book.title,
            bookAuthor: authorName,
            fileExtension: fileExtension,
            totalBytes: 0,
            bytesDownloaded: 0,
            startedAt: Date()
        )
        savePendingDownloadsInfo(pending)
    }

    /// Update progress for a pending download
    private func updatePendingDownloadProgress(bookId: String, bytesDownloaded: Int64, totalBytes: Int64) {
        var pending = loadPendingDownloadsInfo()
        if var info = pending[bookId] {
            info.bytesDownloaded = bytesDownloaded
            info.totalBytes = totalBytes
            pending[bookId] = info
            savePendingDownloadsInfo(pending)
        }
    }

    /// Remove a pending download (completed, cancelled, or failed)
    private func removePendingDownloadInfo(bookId: String) {
        var pending = loadPendingDownloadsInfo()
        pending.removeValue(forKey: bookId)
        savePendingDownloadsInfo(pending)
        DebugLogger.download("Removed pending download: \(bookId)")
    }

    /// Restore pending downloads on app launch
    ///
    /// Creates placeholder ActiveDownload entries from persisted info,
    /// then queries the background session to reconcile with actual task state.
    private func restorePendingDownloads() {
        let pending = loadPendingDownloadsInfo()

        guard !pending.isEmpty else {
            DebugLogger.download("No pending downloads to restore")
            return
        }

        DebugLogger.download("Restoring \(pending.count) pending downloads")

        // Create placeholder ActiveDownload entries for UI
        for (bookId, info) in pending {
            // Restore file extension to thread-safe storage
            fileExtensionStorage.set(info.fileExtension, for: bookId)

            // Create a placeholder Book for UI display
            let placeholderAuthor = Author(id: UUID(), name: info.bookAuthor)
            let placeholderBook = Book(
                id: UUID(uuidString: bookId) ?? UUID(),
                asin: "", // Placeholder - not needed for UI
                title: info.bookTitle,
                archiveStatus: .available,
                authors: [placeholderAuthor]
            )

            activeDownloads[bookId] = ActiveDownload(
                id: bookId,
                book: placeholderBook,
                bytesDownloaded: info.bytesDownloaded,
                totalBytes: info.totalBytes,
                state: .downloading(progress: info.totalBytes > 0
                    ? Double(info.bytesDownloaded) / Double(info.totalBytes)
                    : 0),
                task: nil
            )

            // Store placeholder book for completion handler
            pendingBooks[bookId] = placeholderBook
        }

        // Query background session for actual task state
        downloadSession.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                self?.reconcileWithBackgroundTasks(tasks)
            }
        }
    }

    /// Reconcile restored state with actual background session tasks
    private func reconcileWithBackgroundTasks(_ tasks: [URLSessionTask]) {
        let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
        let taskBookIds = Set(downloadTasks.compactMap { $0.taskDescription })
        let pendingBookIds = Set(activeDownloads.keys)

        DebugLogger.download("Reconciling: \(downloadTasks.count) tasks, \(pendingBookIds.count) pending")

        // Update active downloads with actual task references
        for task in downloadTasks {
            guard let bookId = task.taskDescription else { continue }

            self.downloadTasks[bookId] = task

            if var download = activeDownloads[bookId] {
                download.task = task
                activeDownloads[bookId] = download
                DebugLogger.download("Linked task for: \(bookId)")
            }
        }

        // Remove pending downloads that don't have corresponding tasks
        // (they either completed while app was terminated, or were cancelled)
        for bookId in pendingBookIds where !taskBookIds.contains(bookId) {
            // Check if it completed while we were away
            if storageManager.isBookDownloaded(bookId: bookId) {
                DebugLogger.download("Download completed while app was terminated: \(bookId)")
                activeDownloads[bookId]?.state = .completed

                // Remove from active after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.activeDownloads.removeValue(forKey: bookId)
                }
            } else {
                // No task and not downloaded - was cancelled or failed
                DebugLogger.download("Download task not found, removing: \(bookId)")
                activeDownloads.removeValue(forKey: bookId)
                pendingBooks.removeValue(forKey: bookId)
                fileExtensionStorage.remove(for: bookId)
            }

            removePendingDownloadInfo(bookId: bookId)
        }
    }

    // MARK: - Session Handling

    /// Handle background session events (called from AppDelegate)
    ///
    /// When a background download completes while the app is suspended or terminated,
    /// iOS relaunches the app and calls AppDelegate's handleEventsForBackgroundURLSession.
    /// This method stores the completion handler and reconnects to the background session.
    ///
    /// - Parameters:
    ///   - identifier: The session identifier from iOS
    ///   - completionHandler: Must be called after all events are processed
    func handleBackgroundSessionEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == sessionIdentifier else {
            DebugLogger.download("Unknown session identifier: \(identifier), expected: \(sessionIdentifier)")
            completionHandler()
            return
        }

        DebugLogger.download("Handling background session events for: \(identifier)")

        // Store completion handler - will be called in urlSessionDidFinishEvents
        backgroundCompletionHandler = completionHandler

        // Accessing downloadSession triggers reconnection to the background session
        // This causes the delegate methods to be called for any completed downloads
        _ = downloadSession
    }
}

// MARK: URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _: URLSession,
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
        let fileExtension = fileExtensionStorage.get(for: bookId)
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
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
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
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let bookId = downloadTask.taskDescription else { return }

        if let error {
            Task { @MainActor in
                handleDownloadError(bookId: bookId, error: error)
            }
        }
    }

    /// Called when all background session events have been delivered
    ///
    /// This is called after all downloads complete (success or failure) when the app
    /// was relaunched to handle background session events. We must call the completion
    /// handler stored in handleBackgroundSessionEvents to tell iOS we're done.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DebugLogger.download("All background session events delivered")

        Task { @MainActor in
            // Call the completion handler to tell iOS we're done updating UI
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
            DebugLogger.download("Background completion handler called")
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
        let fileExtension = fileExtensionStorage.get(for: bookId)

        // Get file size using explicit extension (metadata not saved yet)
        let fileSize = storageManager.downloadedFileSize(for: bookId, extension: fileExtension) ?? 0

        // Update metadata with file extension
        storageManager.addToMetadata(book: book, fileSize: fileSize, fileExtension: fileExtension)

        // Update state
        activeDownloads[bookId]?.state = .completed
        downloadTasks.removeValue(forKey: bookId)
        pendingBooks.removeValue(forKey: bookId)
        fileExtensionStorage.remove(for: bookId) // Clean up thread-safe storage
        removePendingDownloadInfo(bookId: bookId) // Clean up persisted pending info
        clearResumeData(bookId: bookId) // Clean up any stale resume data

        // Remove from active downloads after short delay (to show completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.activeDownloads.removeValue(forKey: bookId)
        }

        DebugLogger.success("Download complete: \(book.title) saved to \(savedPath.lastPathComponent)")
    }

    private func updateProgress(bookId: String, bytesWritten: Int64, totalBytes: Int64) {
        guard var download = activeDownloads[bookId] else { return }

        let previousProgress = download.progress
        download.bytesDownloaded = bytesWritten
        if totalBytes > 0 {
            download.totalBytes = totalBytes
        }

        let progress = download.progress
        download.state = .downloading(progress: progress)

        activeDownloads[bookId] = download

        // Persist progress periodically (every 5%) for app restart recovery
        // This avoids excessive writes while ensuring reasonable progress preservation
        let previousPercent = Int(previousProgress * 20) // 5% increments
        let currentPercent = Int(progress * 20)
        if currentPercent > previousPercent {
            updatePendingDownloadProgress(bookId: bookId, bytesDownloaded: bytesWritten, totalBytes: totalBytes)
        }
    }

    private func handleDownloadError(bookId: String, error: Error) {
        let nsError = error as NSError

        // Check if cancelled (already handled by cancelDownload)
        if nsError.code == NSURLErrorCancelled {
            activeDownloads.removeValue(forKey: bookId)
            removePendingDownloadInfo(bookId: bookId)
            clearResumeData(bookId: bookId)
            return
        }

        // Check for resumable network errors with resume data
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            saveResumeData(bookId: bookId, data: resumeData)

            // Set to paused state since we can resume
            let progress = activeDownloads[bookId]?.progress ?? 0
            activeDownloads[bookId]?.state = .paused(progress: progress)

            DebugLogger.download("Saved resume data for \(bookId), can retry later")
            return
        }

        // Update state with error
        let errorMessage = error.localizedDescription
        activeDownloads[bookId]?.state = .failed(error: errorMessage)

        // Remove pending info - user will need to retry from scratch
        removePendingDownloadInfo(bookId: bookId)
        clearResumeData(bookId: bookId)

        DebugLogger.error("Download failed: \(bookId)", error: error)
    }

    // MARK: - Resume Data Persistence

    /// Save resume data for a failed download
    private func saveResumeData(bookId: String, data: Data) {
        let key = resumeDataKeyPrefix + bookId
        userDefaults.set(data, forKey: key)
        DebugLogger.download("Saved \(data.count) bytes of resume data for \(bookId)")
    }

    /// Load resume data for a download
    private func loadResumeData(bookId: String) -> Data? {
        let key = resumeDataKeyPrefix + bookId
        return userDefaults.data(forKey: key)
    }

    /// Clear resume data after successful resume or cancellation
    private func clearResumeData(bookId: String) {
        let key = resumeDataKeyPrefix + bookId
        userDefaults.removeObject(forKey: key)
    }

    /// Check if resume data exists for a download
    func hasResumeData(bookId: String) -> Bool {
        loadResumeData(bookId: bookId) != nil
    }
}

// MARK: - DebugLogger Extension for Downloads

extension DebugLogger {
    static func download(_ message: String) {
        log(message, category: .info) // Use info category for download operations
    }
}
