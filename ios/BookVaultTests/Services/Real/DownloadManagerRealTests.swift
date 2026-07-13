//
//  DownloadManagerRealTests.swift
//  BookVaultTests
//
//  Phase 4: Real service tests for DownloadManager.
//  Tests actual download logic with mock dependencies.
//

import XCTest
@testable import BookVault

// MARK: - MockStorageManagerForDownloads

@MainActor
final class MockStorageManagerForDownloads: StorageManaging {
    var downloads: [DownloadedBook] = []
    var totalSize: Int64 = 0
    var isLoading = false
    var storageLimit: Int64 = 10_000_000_000 // 10 GB
    var availableDeviceSpace: Int64 = 50_000_000_000 // 50 GB
    var remainingStorageLimit: Int64 { storageLimit - totalSize }
    var storageUsagePercentage: Double { Double(totalSize) / Double(storageLimit) }
    var isNearStorageLimit: Bool { storageUsagePercentage > 0.9 }

    var downloadedBookIds: Set<String> = []
    var canDownloadResult = true
    var savedAudioFiles: [String: URL] = [:]
    var savedCoverImages: [String: Data] = [:]
    var metadataEntries: [String: (book: Book, fileSize: Int64, fileExtension: String)] = [:]

    func audioFilePath(for bookId: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId).mp3")
    }

    func audioFilePath(for bookId: String, extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId).\(fileExtension)")
    }

    func coverImagePath(for bookId: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(bookId).jpg")
    }

    func saveAudioFile(from _: URL, bookId: String) throws -> URL {
        let destURL = audioFilePath(for: bookId)
        savedAudioFiles[bookId] = destURL
        return destURL
    }

    func saveCoverImage(data: Data, bookId: String) throws {
        savedCoverImages[bookId] = data
    }

    func isBookDownloaded(bookId: String) -> Bool {
        downloadedBookIds.contains(bookId)
    }

    func downloadedFileSize(for bookId: String) -> Int64? {
        metadataEntries[bookId]?.fileSize
    }

    func downloadedFileSize(for bookId: String, extension _: String?) -> Int64? {
        metadataEntries[bookId]?.fileSize
    }

    func deleteDownload(bookId: String) throws {
        downloadedBookIds.remove(bookId)
        metadataEntries.removeValue(forKey: bookId)
    }

    func deleteAllDownloads() throws {
        downloadedBookIds.removeAll()
        metadataEntries.removeAll()
    }

    func addToMetadata(book: Book, fileSize: Int64, fileExtension: String) {
        downloadedBookIds.insert(book.id.uuidString)
        metadataEntries[book.id.uuidString] = (book: book, fileSize: fileSize, fileExtension: fileExtension)
    }

    func getDownloadedBook(bookId: String) -> DownloadedBook? {
        guard let entry = metadataEntries[bookId] else { return nil }
        return DownloadedBook(
            id: bookId,
            title: entry.book.title,
            author: entry.book.authors.first?.name ?? "",
            downloadedAt: Date(),
            fileSize: entry.fileSize,
            audioPath: "audiobooks/\(bookId).mp3",
            coverPath: nil,
            fileExtension: entry.fileExtension
        )
    }

    func canDownload(fileSize _: Int64) -> Bool {
        canDownloadResult
    }

    func verifyDownload(bookId: String) -> Bool {
        downloadedBookIds.contains(bookId)
    }

    func cleanupOrphanedFiles() {
        // No-op for tests
    }
}

// MARK: - MockNetworkMonitorForDownloads

@MainActor
final class MockNetworkMonitorForDownloads: NetworkMonitoring {
    @Published var isConnected = true
    @Published var isExpensive = false
    @Published var connectionType: ConnectionType = .wifi
    @Published var isOnline = true
    @Published var canDownload = true
    @Published var downloadBlockedReason: String?

    func refreshStatus() {}
    func restartMonitor() {}

    func waitForConnection(timeout _: TimeInterval) async -> Bool {
        isConnected
    }
}

// MARK: - DownloadManagerRealTests

@MainActor
final class DownloadManagerRealTests: XCTestCase {
    var sut: DownloadManager!
    var mockAPIClient: MockAPIClient!
    var mockStorageManager: MockStorageManagerForDownloads!
    var mockNetworkMonitor: MockNetworkMonitorForDownloads!
    var testDefaultsSuiteName: String!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        mockAPIClient.accessToken = "test-token"
        mockStorageManager = MockStorageManagerForDownloads()
        mockNetworkMonitor = MockNetworkMonitorForDownloads()

        // Isolated UserDefaults so pending-download persistence doesn't leak between tests
        testDefaultsSuiteName = "com.bookvault.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)

        // Create with a test session identifier and nil session (won't create background session)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let testSession = URLSession(configuration: config)

        sut = DownloadManager(
            apiClient: mockAPIClient,
            storageManager: mockStorageManager,
            networkMonitor: mockNetworkMonitor,
            sessionIdentifier: "com.bookvault.downloads.test.\(UUID().uuidString)",
            userDefaults: testDefaults,
            session: testSession
        )
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        sut = nil
        mockAPIClient = nil
        mockStorageManager = nil
        mockNetworkMonitor = nil
        testDefaults = nil
        testDefaultsSuiteName = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertTrue(sut.activeDownloads.isEmpty)
        XCTAssertNil(sut.error)
    }

    // MARK: - Download State Tests

    func testDownloadStateNotDownloaded() {
        let bookId = UUID().uuidString

        let state = sut.downloadState(for: bookId)

        XCTAssertEqual(state, .notDownloaded)
    }

    func testDownloadStateCompleted() {
        let bookId = UUID().uuidString
        mockStorageManager.downloadedBookIds.insert(bookId)

        let state = sut.downloadState(for: bookId)

        XCTAssertEqual(state, .completed)
    }

    func testDownloadStateWhenActivelyDownloading() {
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        // Simulate active download
        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 1000,
            totalBytes: 10000,
            state: .downloading(progress: 0.1),
            task: nil
        )
        sut.activeDownloads[bookId] = activeDownload

        let state = sut.downloadState(for: bookId)

        if case .downloading = state {
            // Expected
        } else {
            XCTFail("Expected downloading state, got \(state)")
        }
    }

    // MARK: - Is Downloading Tests

    func testIsDownloadingWhenNotDownloading() {
        let bookId = UUID().uuidString

        XCTAssertFalse(sut.isDownloading(bookId: bookId))
    }

    func testIsDownloadingWhenWaiting() {
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 0,
            totalBytes: 0,
            state: .waiting,
            task: nil
        )
        sut.activeDownloads[bookId] = activeDownload

        XCTAssertTrue(sut.isDownloading(bookId: bookId))
    }

    func testIsDownloadingWhenActivelyDownloading() {
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 5000,
            totalBytes: 10000,
            state: .downloading(progress: 0.5),
            task: nil
        )
        sut.activeDownloads[bookId] = activeDownload

        XCTAssertTrue(sut.isDownloading(bookId: bookId))
    }

    func testIsDownloadingWhenPaused() {
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 5000,
            totalBytes: 10000,
            state: .paused(progress: 0.5),
            task: nil
        )
        sut.activeDownloads[bookId] = activeDownload

        // Paused is not considered "downloading"
        XCTAssertFalse(sut.isDownloading(bookId: bookId))
    }

    // MARK: - WiFi Required Tests

    func testStartDownloadFailsWhenWiFiRequired() async {
        // Given
        mockNetworkMonitor.canDownload = false

        let book = TestFixtures.makeBook()

        // When/Then
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected WiFi required error")
        } catch let error as DownloadError {
            if case .wifiRequired = error {
                // Expected
            } else {
                XCTFail("Expected wifiRequired, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Already Downloaded Tests

    func testStartDownloadSkipsAlreadyDownloaded() async throws {
        // Given
        let book = TestFixtures.makeBook()
        mockStorageManager.downloadedBookIds.insert(book.id.uuidString)

        // When
        try await sut.startDownload(book: book)

        // Then - no active download should be created
        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    // MARK: - Eligibility Tests (via APIClient seam)

    func testStartDownloadNotEligible() async {
        // Given
        let book = TestFixtures.makeBook()
        mockAPIClient.checkDownloadEligibilityResult = .success(
            CheckDownloadEligibility200Response(eligible: false)
        )

        // When/Then
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected notEligible error")
        } catch let error as DownloadError {
            XCTAssertEqual(error, .notEligible)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(mockAPIClient.checkDownloadEligibilityCalls, [book.id])
        XCTAssertTrue(mockAPIClient.generateDownloadUrlCalls.isEmpty)
        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    func testStartDownloadEligibilityUnauthorized() async {
        // Given
        let book = TestFixtures.makeBook()
        mockAPIClient.checkDownloadEligibilityResult = .failure(APIError.unauthorized)

        // When/Then
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected unauthorized error")
        } catch let error as DownloadError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    func testStartDownloadEligibilityRateLimited() async {
        // Given
        let book = TestFixtures.makeBook()
        mockAPIClient.checkDownloadEligibilityResult = .failure(APIError.serverError(429, nil))

        // When/Then
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected rateLimitExceeded error")
        } catch let error as DownloadError {
            XCTAssertEqual(error, .rateLimitExceeded)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    // MARK: - URL Generation Tests (via APIClient seam)

    func testStartDownloadSuccessStartsDownloadTask() async throws {
        // Given
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString
        mockAPIClient.checkDownloadEligibilityResult = .success(
            CheckDownloadEligibility200Response(eligible: true)
        )
        mockAPIClient.generateDownloadUrlResult = .success(GenerateDownloadUrl200Response(
            downloadUrl: "https://s3.example.com/audiobooks/test.mp3?signature=abc",
            expiresAt: Date().addingTimeInterval(3600),
            fileSize: 1_000_000
        ))
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("audio".utf8))
        }

        // When
        try await sut.startDownload(book: book)

        // Then - both API calls went through the injected client
        XCTAssertEqual(mockAPIClient.checkDownloadEligibilityCalls, [book.id])
        XCTAssertEqual(mockAPIClient.generateDownloadUrlCalls.count, 1)
        XCTAssertEqual(mockAPIClient.generateDownloadUrlCalls.first?.bookId, book.id)

        // And the download task was started with the returned URL info
        let download = try XCTUnwrap(sut.activeDownloads[bookId])
        XCTAssertEqual(download.state, .downloading(progress: 0))
        XCTAssertEqual(download.totalBytes, 1_000_000)
        XCTAssertNotNil(download.task)

        // Cleanup - cancel the in-flight task
        sut.cancelDownload(bookId: bookId)
    }

    func testStartDownloadUrlGenerationRequiresS3() async {
        // Given
        let book = TestFixtures.makeBook()
        mockAPIClient.checkDownloadEligibilityResult = .success(
            CheckDownloadEligibility200Response(eligible: true)
        )
        mockAPIClient.generateDownloadUrlResult = .failure(APIError.serverError(501, nil))

        // When/Then
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected networkError")
        } catch let error as DownloadError {
            XCTAssertEqual(error, .networkError("Downloads require S3 configuration"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    func testStartDownloadInsufficientStorage() async {
        // Given
        let book = TestFixtures.makeBook()
        mockStorageManager.canDownloadResult = false
        mockAPIClient.checkDownloadEligibilityResult = .success(
            CheckDownloadEligibility200Response(eligible: true)
        )
        mockAPIClient.generateDownloadUrlResult = .success(GenerateDownloadUrl200Response(
            downloadUrl: "https://s3.example.com/audiobooks/test.mp3",
            expiresAt: Date().addingTimeInterval(3600),
            fileSize: 999_000_000_000
        ))

        // When/Then
        do {
            try await sut.startDownload(book: book)
            XCTFail("Expected insufficientStorage error")
        } catch let error as DownloadError {
            XCTAssertEqual(error, .insufficientStorage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sut.activeDownloads.isEmpty)
    }

    // MARK: - Cancel Download Tests

    func testCancelDownload() {
        // Given
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 1000,
            totalBytes: 10000,
            state: .downloading(progress: 0.1),
            task: nil
        )
        sut.activeDownloads[bookId] = activeDownload

        // When
        sut.cancelDownload(bookId: bookId)

        // Then
        XCTAssertNil(sut.activeDownloads[bookId])
    }

    // MARK: - Delete Download Tests

    func testDeleteDownload() throws {
        // Given
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString
        mockStorageManager.downloadedBookIds.insert(bookId)

        // When
        try sut.deleteDownload(bookId: bookId)

        // Then - storage manager should have deleted
        XCTAssertFalse(mockStorageManager.downloadedBookIds.contains(bookId))
    }

    // MARK: - Active Download Progress Tests

    func testActiveDownloadProgress() {
        // Given
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        var activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 2500,
            totalBytes: 10000,
            state: .downloading(progress: 0.25),
            task: nil
        )

        // Then
        XCTAssertEqual(activeDownload.progress, 0.25, accuracy: 0.001)

        // Update progress
        activeDownload.bytesDownloaded = 5000
        XCTAssertEqual(activeDownload.progress, 0.5, accuracy: 0.001)
    }

    func testActiveDownloadProgressWithZeroTotal() {
        // Given
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 1000,
            totalBytes: 0,
            state: .downloading(progress: 0),
            task: nil
        )

        // Then - should handle division by zero
        XCTAssertEqual(activeDownload.progress, 0)
    }

    // MARK: - Formatted Progress Tests

    func testActiveDownloadFormattedProgress() {
        // Given
        let book = TestFixtures.makeBook()
        let bookId = book.id.uuidString

        let activeDownload = ActiveDownload(
            id: bookId,
            book: book,
            bytesDownloaded: 5_000_000, // 5 MB
            totalBytes: 100_000_000, // 100 MB
            state: .downloading(progress: 0.05),
            task: nil
        )

        // Then
        let formatted = activeDownload.formattedProgress
        XCTAssertTrue(formatted.contains("MB"))
    }

    // MARK: - Download State Equatable Tests

    func testDownloadStateEquatable() {
        XCTAssertEqual(DownloadState.notDownloaded, DownloadState.notDownloaded)
        XCTAssertEqual(DownloadState.waiting, DownloadState.waiting)
        XCTAssertEqual(DownloadState.completed, DownloadState.completed)
        XCTAssertEqual(DownloadState.downloading(progress: 0.5), DownloadState.downloading(progress: 0.5))
        XCTAssertEqual(DownloadState.paused(progress: 0.3), DownloadState.paused(progress: 0.3))
        XCTAssertEqual(DownloadState.failed(error: "Error"), DownloadState.failed(error: "Error"))

        XCTAssertNotEqual(DownloadState.notDownloaded, DownloadState.completed)
        XCTAssertNotEqual(DownloadState.downloading(progress: 0.5), DownloadState.downloading(progress: 0.6))
    }

    // MARK: - Error Description Tests

    func testDownloadErrorDescriptions() {
        XCTAssertNotNil(DownloadError.networkError("Test").errorDescription)
        XCTAssertNotNil(DownloadError.insufficientStorage.errorDescription)
        XCTAssertNotNil(DownloadError.rateLimitExceeded.errorDescription)
        XCTAssertNotNil(DownloadError.urlExpired.errorDescription)
        XCTAssertNotNil(DownloadError.fileCorruption.errorDescription)
        XCTAssertNotNil(DownloadError.unauthorized.errorDescription)
        XCTAssertNotNil(DownloadError.notEligible.errorDescription)
        XCTAssertNotNil(DownloadError.wifiRequired.errorDescription)
        XCTAssertNotNil(DownloadError.cancelled.errorDescription)
    }
}
