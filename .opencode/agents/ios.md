---
description: Book Vault iOS agent. Use for Swift/SwiftUI work in the ios/ directory — new views, services, model changes, XcodeGen config, SwiftLint fixes, and keeping the iOS client in sync with API changes.
mode: subagent
---

# Book Vault iOS Agent

You are working on the **Swift/SwiftUI iOS client** for Book Vault, located in `ios/BookVault/`. The app targets iPhone, uses XcodeGen for project generation, and is in full production with all 8 phases complete.

## Project layout

```
ios/
├── project.yml                    XcodeGen project definition
├── .swiftlint.yml                 SwiftLint rules
├── .swiftformat                   SwiftFormat config
└── BookVault/
    ├── BookVaultApp.swift         App entry point
    ├── ContentView.swift          Root tab/content view
    ├── Views/                     SwiftUI views (Auth, Books, Browse, Library,
    │                              Search, Downloads, Player, Settings)
    ├── Services/                  23 service files (APIClient, AuthManager,
    │                              AudioPlayerManager, DownloadManager,
    │                              SyncManager, ProgressManager, etc.)
    ├── Generated/Models/          ~105 auto-generated Swift models (never edit)
    ├── Models/                    Manual models (UserProgress.swift)
    ├── Extensions/
    └── Utilities/
```

## Critical rules

1. **Never edit `Generated/Models/`** — These are auto-generated from `docs/api/openapi.yaml`. To change a model, update the OpenAPI spec and run:

   ```bash
   npm run api:generate:swift
   ```

2. **After changing `project.yml`**, always regenerate the Xcode project:

   ```bash
   cd ios && xcodegen generate
   ```

3. **SwiftLint compliance** — All Swift code must pass SwiftLint. Check locally:

   ```bash
   cd ios && swiftlint
   ```

4. **Test new services** — Add tests under `ios/BookVaultTests/Services/`. Use existing `Mocks/` and `Helpers/` patterns.

## Key services

| Service                                            | Responsibility                                           |
| -------------------------------------------------- | -------------------------------------------------------- |
| `APIClient.swift`                                  | HTTP client using generated models; handles auth headers |
| `AuthManager.swift`                                | JWT token storage (Keychain), refresh flow               |
| `AudioPlayerManager.swift`                         | AVPlayer wrapper; background audio, lock screen controls |
| `AuthenticatedAVAssetResourceLoaderDelegate.swift` | Inject auth headers for S3 streaming                     |
| `DownloadManager.swift`                            | Background URLSession downloads, offline storage         |
| `SyncManager.swift`                                | Progress sync to/from server                             |
| `ProgressManager.swift`                            | Local + remote progress merging                          |
| `OfflineProgressStore.swift`                       | UserDefaults-based offline persistence                   |
| `LibraryManager.swift`                             | Library CRUD, caching                                    |
| `NetworkMonitor.swift`                             | Reachability; gates network calls                        |

## Auth pattern

The iOS app uses custom JWT — not NextAuth cookies. `AuthManager` stores tokens in the iOS Keychain. `APIClient` attaches `Authorization: Bearer <token>` to every request. Token refresh hits `/api/auth/mobile/refresh`.

## Audio streaming

S3 audio is served via presigned URLs (`/api/audio/...`). `AuthenticatedAVAssetResourceLoaderDelegate` intercepts AVAsset resource loads to inject the Bearer token, enabling authenticated streaming without exposing credentials in the URL.

## Adding a new feature — checklist

1. If the feature requires new API data: update `docs/api/openapi.yaml` first (use the `api-planner` agent), run `npm run api:generate:swift` to update `Generated/Models/`
2. Create or update the relevant `Service` file
3. Create or update `View` files using SwiftUI
4. If navigation changes: update `ContentView.swift` or the relevant parent view
5. Write tests in `ios/BookVaultTests/Services/` or `Integration/`
6. Run `swiftlint` and fix any warnings
7. Run `cd ios && xcodegen generate` if `project.yml` changed
8. Build and test: `xcodebuild build -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 16'`

## Roadmap items (next up)

- Remove volume slider from audio playback view
- Add duration remaining display to audio playback view
- Add dismiss button to mini-player
- Sleep timer functionality (fade-out and pause after duration)
- Cold storage retrieval warning (S3 Glacier restore — see `docs/s3-archive-restore-workflow.md`)
