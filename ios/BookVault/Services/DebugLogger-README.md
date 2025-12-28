# DebugLogger Usage Guide

## Overview

`DebugLogger` is a centralized debug logging utility that eliminates the need to scatter `#if DEBUG` directives throughout the codebase. All logging is automatically disabled in release builds.

## Key Features

- **Automatic Debug/Release Switching**: No need for `#if DEBUG` everywhere
- **Categorized Logging**: Network, Auth, Audio, Database, UI, etc.
- **Visual Indicators**: Emoji prefixes for quick log scanning
- **Performance Measurement**: Built-in timing utilities
- **OSLog Integration**: Better Xcode Console and Instruments support
- **Verbose Mode**: Toggle detailed logging at runtime

## Basic Usage

### Simple Logging

```swift
// General debug message
DebugLogger.log("Something happened")

// Error with optional Error object
DebugLogger.error("Failed to load data", error: someError)

// Success message
DebugLogger.success("Data saved successfully")

// Warning
DebugLogger.warning("Deprecated API used")

// Info
DebugLogger.info("User logged in")
```

### Categorized Logging

```swift
// Network requests/responses
DebugLogger.network("Fetching books from API")

// Authentication operations
DebugLogger.auth("Token refreshed successfully")

// Audio playback
DebugLogger.audio("Player state changed to playing")

// Database operations
DebugLogger.database("Cached 50 books")

// UI events
DebugLogger.ui("Navigated to book detail view")
```

### Specialized Logging

#### API Requests

```swift
DebugLogger.apiRequest(
    method: "GET",
    path: "/api/books",
    body: requestBody
)
```

#### API Responses

```swift
DebugLogger.apiResponse(
    path: "/api/books",
    statusCode: 200,
    body: responseBody
)
```

#### Performance Measurement

```swift
// Synchronous operation
let result = DebugLogger.measure("Load books from cache") {
    return loadBooksFromCache()
}
// Logs: "⚡️ Load books from cache completed in 15.42ms"

// Async operation
let books = await DebugLogger.measure("Fetch books from API") {
    return await fetchBooksFromAPI()
}
// Logs: "⚡️ Fetch books from API completed in 234.56ms"
```

#### Object Dumping

```swift
DebugLogger.dump(complexObject, label: "User object")
```

### Verbose Logging

For detailed debugging that would be too noisy in normal use:

```swift
// Only logs if DebugLogger.verboseLoggingEnabled = true
DebugLogger.verbose("Detailed state: \(largeObject)")

// Toggle verbose mode at runtime (debug builds only)
DebugLogger.verboseLoggingEnabled = false
```

### Debug-Only Code Execution

```swift
// Execute code only in debug builds (without logging)
DebugLogger.debugOnly {
    // Setup test data, inject debug tools, etc.
    setupDebugMenu()
}

// Async version
await DebugLogger.debugOnly {
    await loadTestFixtures()
}
```

## Migration Examples

### Before (scattered `#if DEBUG`)

```swift
#if DEBUG
print("🌐 APIClient initialized with base URL: \(urlString)")
#endif

// Later in the code...
#if DEBUG
if enableDebugLogging {
    print("📡 API Response:")
    print("   URL: \(url)")
    print("   Status: \(statusCode)")
}
#endif

// And again...
#if DEBUG
print("❌ Decoding Error: \(error)")
#endif
```

### After (using DebugLogger)

```swift
DebugLogger.network("APIClient initialized with base URL: \(urlString)")

// Later in the code...
DebugLogger.apiResponse(
    path: url,
    statusCode: statusCode,
    body: responseBody
)

// And again...
DebugLogger.error("Failed to decode response", error: error)
```

## Log Categories & Emojis

| Category       | Emoji | Use Case                           |
| -------------- | ----- | ---------------------------------- |
| `.network`     | 🌐    | API requests, network operations   |
| `.auth`        | 🔐    | Login, logout, token refresh       |
| `.audio`       | 🎵    | Audio playback, player state       |
| `.database`    | 💾    | Cache operations, data persistence |
| `.ui`          | 🖼️    | View lifecycle, navigation         |
| `.error`       | ❌    | Errors and failures                |
| `.warning`     | ⚠️    | Warnings and deprecations          |
| `.success`     | ✅    | Successful operations              |
| `.info`        | ℹ️    | General information                |
| `.debug`       | 🐛    | Debug messages (default)           |
| `.performance` | ⚡️    | Performance metrics and timing     |

## Advanced Features

### OSLog Integration (iOS 14+)

For better Xcode Console filtering and Instruments integration:

```swift
DebugLogger.osLog("Network request started", level: .info, category: "networking")
```

### Runtime Configuration

```swift
// Disable all logging at runtime (debug builds only)
// Useful for performance testing or reducing noise
DebugLogger.verboseLoggingEnabled = false

// Re-enable later
DebugLogger.verboseLoggingEnabled = true
```

## Best Practices

1. **Use appropriate categories**: Makes logs easier to filter and understand
2. **Use `verbose()` for detailed logs**: Prevents log spam during normal debugging
3. **Use `measure()` for performance-critical code**: Track and optimize slow operations
4. **Include context in messages**: "Failed to load books" is better than "Load failed"
5. **Use `error()` with Error objects**: Provides more diagnostic information
6. **Don't log sensitive data**: Even in debug builds (passwords, tokens, etc.)

## Performance Impact

- **Debug builds**: Minimal overhead (simple string formatting)
- **Release builds**: Zero overhead (all calls compile to no-ops)

## Testing Helpers

```swift
// Setup test environment (debug only)
DebugLogger.debugOnly {
    // Inject mock data
    // Setup debug UI
    // Configure test environment
}

// Performance testing
let benchmark = DebugLogger.measure("Complex calculation") {
    performComplexCalculation()
}
```

## Example: Refactoring Existing Code

**Before:**

```swift
class AudioPlayerManager {
    func play() {
        #if DEBUG
        print("▶️ Starting playback")
        #endif

        // Play logic...

        #if DEBUG
        print("✅ Playback started")
        #endif
    }
}
```

**After:**

```swift
class AudioPlayerManager {
    func play() {
        DebugLogger.audio("Starting playback")

        // Play logic...

        DebugLogger.success("Playback started")
    }
}
```

## Troubleshooting

### Logs not appearing in release builds

This is expected behavior. Logs are automatically disabled in release builds for performance and security.

### Too many logs

Use `DebugLogger.verboseLoggingEnabled = false` to reduce noise, or switch verbose logs to use `.verbose()` instead of `.log()`.

### Logs appearing in Xcode Console but not in Instruments

Use `DebugLogger.osLog()` for better Instruments integration.

## Future Enhancements (Potential)

- Remote logging to backend (opt-in for crash investigation)
- Log export to file for sharing
- Custom log destinations (CloudWatch, Sentry, etc.)
- Log filtering by category at runtime
- Performance analytics dashboard
