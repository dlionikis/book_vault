# iOS Architecture

**Status**: ✅ Implementation Complete (Reference Document)
**Last Updated**: December 29, 2025

> **TL;DR**: SwiftUI + MVVM architecture with service layer for API calls and AVPlayer for audio.
>
> **Note**: This document contains patterns and examples from the completed iOS implementation. Use as reference for debugging or understanding architecture decisions.

---

## App Structure

```
ios/BookVault/
├── App/
│   ├── BookVaultApp.swift           # App entry point
│   └── AppState.swift                # Global state management
│
├── Features/
│   ├── Auth/
│   │   ├── Views/
│   │   │   └── LoginView.swift
│   │   ├── ViewModels/
│   │   │   └── LoginViewModel.swift
│   │   └── Services/
│   │       └── AuthService.swift
│   │
│   ├── Home/
│   │   ├── Views/
│   │   │   ├── HomeView.swift
│   │   │   └── ContinueListeningRow.swift
│   │   └── ViewModels/
│   │       └── HomeViewModel.swift
│   │
│   ├── Browse/
│   │   ├── Views/
│   │   │   ├── BooksListView.swift
│   │   │   ├── BookDetailView.swift
│   │   │   ├── BookCard.swift
│   │   │   └── SearchView.swift
│   │   └── ViewModels/
│   │       ├── BooksListViewModel.swift
│   │       └── BookDetailViewModel.swift
│   │
│   ├── Player/
│   │   ├── Views/
│   │   │   ├── NowPlayingView.swift
│   │   │   ├── PlaybackControls.swift
│   │   │   └── ChapterListView.swift
│   │   ├── ViewModels/
│   │   │   └── PlayerViewModel.swift
│   │   └── Services/
│   │       └── AudioPlayerService.swift
│   │
│   └── Library/
│       ├── Views/
│       │   ├── LibraryView.swift
│       │   └── UserListView.swift
│       └── ViewModels/
│           └── LibraryViewModel.swift
│
├── Networking/
│   ├── APIClient.swift               # URLSession wrapper
│   ├── Endpoints.swift               # API endpoint definitions
│   ├── NetworkError.swift            # Error handling
│   └── Generated/                    # From OpenAPI spec
│       └── Models/
│           ├── Book.swift
│           ├── Author.swift
│           └── UserProgress.swift
│
├── Services/
│   ├── AuthenticationService.swift  # JWT token management (Keychain)
│   ├── AudioPlayerService.swift     # AVPlayer wrapper
│   ├── ProgressService.swift        # Progress sync
│   └── DownloadService.swift        # Offline downloads (Phase 8)
│
├── Models/
│   ├── AppState.swift               # Global app state
│   └── PlayerState.swift            # Audio player state
│
├── Utilities/
│   ├── KeychainHelper.swift         # Keychain access
│   ├── FileManager+Extensions.swift # File utilities
│   └── Date+Extensions.swift        # Date formatting
│
└── Resources/
    ├── Assets.xcassets               # Images, colors
    └── Info.plist                    # App configuration
```

---

## Architecture Patterns

### MVVM (Model-View-ViewModel)

**View** (SwiftUI):

- Declarative UI
- Observes ViewModel state
- No business logic
- Stateless where possible

**ViewModel** (`@MainActor` + `ObservableObject`):

- Manages view state
- Handles user interactions
- Calls services for data/logic
- Publishes state changes

**Model** (Codable structs):

- Data structures
- Generated from OpenAPI spec
- Business logic (computed properties)

**Services** (Singletons or dependency-injected):

- API calls
- Audio playback
- Authentication
- Local storage

### Example: Book Detail Screen

```swift
// MARK: - Model (Generated from OpenAPI)
struct Book: Codable, Identifiable {
    let id: String
    let title: String
    let authors: [Author]
    let coverUrl: String
    let audioUrl: String
    let runtimeMinutes: Int

    var formattedRuntime: String {
        let hours = runtimeMinutes / 60
        let minutes = runtimeMinutes % 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - ViewModel
@MainActor
class BookDetailViewModel: ObservableObject {
    @Published var book: Book?
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient: APIClient
    private let playerService: AudioPlayerService

    init(apiClient: APIClient = .shared,
         playerService: AudioPlayerService = .shared) {
        self.apiClient = apiClient
        self.playerService = playerService
    }

    func loadBook(id: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            book = try await apiClient.getBook(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func playBook() {
        guard let book = book else { return }
        playerService.play(book: book)
    }
}

// MARK: - View
struct BookDetailView: View {
    let bookId: String
    @StateObject private var viewModel = BookDetailViewModel()

    var body: some View {
        ScrollView {
            if let book = viewModel.book {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: URL(string: book.coverUrl))
                        .frame(width: 200, height: 200)

                    Text(book.title)
                        .font(.title)

                    Text(book.authors.map(\.name).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Play") {
                        viewModel.playBook()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
        }
        .task {
            await viewModel.loadBook(id: bookId)
        }
    }
}
```

---

## Key Services

### AuthenticationService

**Responsibilities**:

- JWT token storage (Keychain)
- Token refresh mechanism
- Login/logout flows
- Session management

**Implementation**:

```swift
@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private let keychainHelper = KeychainHelper()
    private let apiClient: APIClient

    func login(email: String, password: String) async throws {
        let response = try await apiClient.login(email: email, password: password)

        // Store token in Keychain
        try keychainHelper.saveToken(response.token)

        currentUser = response.user
        isAuthenticated = true
    }

    func logout() {
        keychainHelper.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }

    func loadSavedSession() {
        if let token = keychainHelper.loadToken() {
            // Validate token with backend
            Task {
                do {
                    currentUser = try await apiClient.validateToken(token)
                    isAuthenticated = true
                } catch {
                    logout()
                }
            }
        }
    }
}
```

---

### AudioPlayerService

**Responsibilities**:

- AVPlayer management
- Background audio setup
- Lock screen integration
- Progress tracking
- Playback state management

**Implementation**:

```swift
@MainActor
class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published var currentBook: Book?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackSpeed: Float = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?

    func play(book: Book, startPosition: Double = 0) {
        currentBook = book

        guard let url = URL(string: book.audioUrl) else { return }

        // Create player
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Seek to saved position
        if startPosition > 0 {
            let time = CMTime(seconds: startPosition, preferredTimescale: 600)
            player?.seek(to: time)
        }

        // Setup background audio
        setupAudioSession()
        setupNowPlaying()
        setupRemoteCommands()

        // Observe time
        setupTimeObserver()

        // Start playback
        player?.play()
        isPlaying = true
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func setupNowPlaying() {
        guard let book = currentBook else { return }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = book.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = book.authors.map(\.name).joined(separator: ", ")
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0

        // Load cover art
        if let url = URL(string: book.coverUrl),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: 15)
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: -15)
            return .success
        }
    }
}
```

---

### APIClient

**Responsibilities**:

- URLSession configuration
- Request/response handling
- Authentication headers
- Error handling

**Implementation**:

```swift
class APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let keychainHelper = KeychainHelper()

    init(baseURL: String = Config.baseURL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func getBooks(page: Int = 1, limit: Int = 20) async throws -> BookListResponse {
        let url = URL(string: "\(baseURL)/api/books?page=\(page)&limit=\(limit)")!
        return try await request(url: url)
    }

    func getBook(id: String) async throws -> Book {
        let url = URL(string: "\(baseURL)/api/books/\(id)")!
        return try await request(url: url)
    }

    private func request<T: Decodable>(url: URL, method: String = "GET") async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method

        // Add JWT token
        if let token = keychainHelper.loadToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

---

## State Management

### App-Level State (AppState)

```swift
@MainActor
class AppState: ObservableObject {
    @Published var authService = AuthenticationService()
    @Published var playerService = AudioPlayerService.shared

    init() {
        authService.loadSavedSession()
    }
}
```

### Environment Injection

```swift
@main
struct BookVaultApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.authService.isAuthenticated {
                MainTabView()
                    .environmentObject(appState.authService)
                    .environmentObject(appState.playerService)
            } else {
                LoginView()
                    .environmentObject(appState.authService)
            }
        }
    }
}
```

---

## Background Audio Configuration

**Info.plist**:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**AVAudioSession Setup**:

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .spokenAudio)
try session.setActive(true)
```

---

## Offline Storage (Phase 8)

**Download Manager**:

```swift
class DownloadService {
    static let shared = DownloadService()

    private let fileManager = FileManager.default
    private lazy var downloadsDirectory: URL = {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Downloads")
    }()

    func download(book: Book) async throws {
        let session = URLSession(configuration: .background(withIdentifier: "com.bookvault.downloads"))
        let url = URL(string: book.audioUrl)!
        let task = session.downloadTask(with: url)
        task.resume()
    }

    func getLocalURL(for book: Book) -> URL? {
        let filename = "\(book.id).m4b"
        let fileURL = downloadsDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
}
```

---

## Testing Architecture

**Unit Tests**:

```swift
// BookVaultTests/Services/APIClientTests.swift
class APIClientTests: XCTestCase {
    var apiClient: APIClient!
    var mockSession: MockURLSession!

    override func setUp() {
        mockSession = MockURLSession()
        apiClient = APIClient(session: mockSession)
    }

    func testGetBooks() async throws {
        // Load fixture
        let fixture = loadFixture("books-list.json")
        mockSession.nextData = fixture

        let response = try await apiClient.getBooks()
        XCTAssertEqual(response.books.count, 10)
    }
}
```

**SwiftUI Previews**:

```swift
#Preview {
    BookDetailView(bookId: "test-id")
        .environmentObject(AuthenticationService())
        .environmentObject(AudioPlayerService.shared)
}
```

---

## Performance Considerations

1. **Image Caching**: Use AsyncImage with cached image loading
2. **List Performance**: Use LazyVStack/LazyVGrid for large lists
3. **Memory Management**: Properly deallocate AVPlayer when not in use
4. **Network Efficiency**: Batch API requests, use pagination
5. **Background Downloads**: Use URLSession background configuration
