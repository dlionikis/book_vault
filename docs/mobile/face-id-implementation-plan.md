# Face ID Authentication Implementation Plan

**Status**: Planned
**Created**: January 1, 2026
**Priority**: Post-launch enhancement
**Estimated Effort**: 5-6 hours

> **TL;DR**
>
> - Enable Face ID/Touch ID login after initial username/password authentication
> - Uses Apple's `LocalAuthentication` framework
> - Stores encrypted password in Keychain with biometric protection
> - No backend changes required (uses existing login API)
> - Graceful fallback to password entry

**Jump to**: [Architecture](#architecture) | [Implementation Steps](#implementation-steps) | [File Changes](#file-changes) | [Testing](#testing)

---

## Overview

### User Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FIRST LOGIN                                  │
├─────────────────────────────────────────────────────────────────────┤
│  1. User enters email + password                                    │
│  2. Login succeeds                                                  │
│  3. Prompt: "Enable Face ID for faster login?"                      │
│  4. If YES → Store encrypted password with biometric protection     │
│  5. Set UserDefaults flag: biometricEnabled = true                  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     SUBSEQUENT LOGINS                               │
├─────────────────────────────────────────────────────────────────────┤
│  1. App checks: biometricEnabled && canUseBiometrics()              │
│  2. Show "Use Face ID" button + password form                       │
│  3. User taps Face ID button                                        │
│  4. Face ID prompt appears                                          │
│  5. SUCCESS → Retrieve stored password → Call login API             │
│  6. FAILURE → Show error, user can enter password manually          │
└─────────────────────────────────────────────────────────────────────┘
```

### Why This Approach

| Approach                            | Backend Changes | Security                            | Complexity |
| ----------------------------------- | --------------- | ----------------------------------- | ---------- |
| **A: Store password (Recommended)** | None            | High (biometric-protected keychain) | Low        |
| B: Device-bound token               | New endpoint    | Higher                              | Medium     |
| C: Passwordless auth                | Major changes   | Highest                             | High       |

**Recommendation**: Approach A - Store the password encrypted in Keychain with biometric access control. This requires zero backend changes and leverages iOS's secure enclave.

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          LoginView                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │  Email Field    │  │ Password Field  │  │ Face ID Button     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘  │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
            ┌───────▼───────┐         ┌───────▼───────┐
            │  AuthManager  │         │ BiometricAuth │
            │               │         │    Manager    │
            │ - login()     │◄────────│               │
            │ - logout()    │         │ - canUse()    │
            │               │         │ - evaluate()  │
            └───────┬───────┘         │ - getPassword │
                    │                 └───────┬───────┘
                    │                         │
            ┌───────▼───────┐         ┌───────▼───────┐
            │  APIClient    │         │ SystemKeychain│
            │               │         │               │
            │ POST /login   │         │ Biometric-    │
            └───────────────┘         │ protected     │
                                      │ password      │
                                      └───────────────┘
```

### Data Storage

| Data                   | Storage      | Protection                                                             |
| ---------------------- | ------------ | ---------------------------------------------------------------------- |
| Access Token           | Keychain     | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`                         |
| Refresh Token          | Keychain     | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`                         |
| User Data              | Keychain     | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`                         |
| **Biometric Password** | Keychain     | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `.biometryCurrentSet` |
| **Biometric Enabled**  | UserDefaults | None (non-sensitive flag)                                              |
| **Biometric Email**    | UserDefaults | None (used to match stored password)                                   |

### Security Considerations

1. **Biometric-protected keychain item**: Uses `SecAccessControlCreateWithFlags` with `.biometryCurrentSet` flag
2. **Invalidation on biometric change**: If user adds/removes Face ID, stored password is invalidated
3. **Device-only storage**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` prevents iCloud sync
4. **Fallback required**: Always allow password login as backup
5. **No password in memory**: Password retrieved only during biometric auth, immediately used, not stored in memory

---

## Implementation Steps

> **Cross-Session Implementation Note**: Each phase includes "Session Start Instructions" to ensure a fresh Claude session has enough context to continue implementation without prior conversation history.

### Phase 1: BiometricAuthManager (Core Logic)

#### Session Start Instructions

1. Read this plan file (`docs/mobile/face-id-implementation-plan.md`)
2. Read `ios/BookVault/Services/SystemKeychain.swift` to understand existing keychain patterns
3. Verify `ios/BookVault/Services/` directory exists

#### Decision: Keychain Approach

This implementation creates a **self-contained** `BiometricAuthManager` with its own keychain methods rather than extending `SystemKeychain`. Rationale:

- Biometric-protected items require different access control flags
- Keeps biometric logic isolated and testable
- `SystemKeychain` remains focused on token storage

**Create**: `ios/BookVault/Services/BiometricAuthManager.swift`

```swift
import LocalAuthentication
import Foundation

/// Manages Face ID / Touch ID authentication
@MainActor
class BiometricAuthManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var biometryType: LABiometryType = .none
    @Published private(set) var canUseBiometrics: Bool = false
    @Published private(set) var isBiometricEnabled: Bool = false

    // MARK: - Constants

    private enum Keys {
        static let biometricEnabled = "biometricEnabled"
        static let biometricEmail = "biometricEmail"
        static let biometricPassword = "com.bookvault.biometricPassword"
    }

    // MARK: - Singleton

    static let shared = BiometricAuthManager()

    private init() {
        checkBiometricAvailability()
        loadBiometricPreference()
    }

    // MARK: - Public Methods

    /// Check if device supports biometric authentication
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        biometryType = context.biometryType
    }

    /// Returns user-friendly name for biometric type
    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometrics"
        }
    }

    /// Authenticate user with biometrics and retrieve stored password
    func authenticateAndGetCredentials() async throws -> (email: String, password: String) {
        guard isBiometricEnabled else {
            throw BiometricError.notEnabled
        }

        guard canUseBiometrics else {
            throw BiometricError.notAvailable
        }

        // Authenticate with biometrics
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Log in to Book Vault"
        )

        guard success else {
            throw BiometricError.authenticationFailed
        }

        // Retrieve stored credentials
        guard let email = UserDefaults.standard.string(forKey: Keys.biometricEmail),
              let password = try retrievePassword() else {
            throw BiometricError.credentialsNotFound
        }

        return (email, password)
    }

    /// Enable biometric login for a user
    func enableBiometric(email: String, password: String) throws {
        // Store password with biometric protection
        try storePassword(password)

        // Store email and enable flag
        UserDefaults.standard.set(email, forKey: Keys.biometricEmail)
        UserDefaults.standard.set(true, forKey: Keys.biometricEnabled)

        isBiometricEnabled = true
    }

    /// Disable biometric login
    func disableBiometric() {
        // Remove stored password
        deletePassword()

        // Clear preferences
        UserDefaults.standard.removeObject(forKey: Keys.biometricEmail)
        UserDefaults.standard.removeObject(forKey: Keys.biometricEnabled)

        isBiometricEnabled = false
    }

    /// Check if biometric is enabled for a specific email
    func isBiometricEnabledFor(email: String) -> Bool {
        guard isBiometricEnabled else { return false }
        let storedEmail = UserDefaults.standard.string(forKey: Keys.biometricEmail)
        return storedEmail?.lowercased() == email.lowercased()
    }

    // MARK: - Private Methods

    private func loadBiometricPreference() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: Keys.biometricEnabled)
    }

    /// Store password with biometric protection
    private func storePassword(_ password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw BiometricError.encodingFailed
        }

        // Create access control with biometric requirement
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw BiometricError.accessControlCreationFailed
        }

        // Delete existing item first
        deletePassword()

        // Add new item with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Keys.biometricPassword,
            kSecValueData as String: passwordData,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricError.keychainSaveFailed(status)
        }
    }

    /// Retrieve password (requires biometric auth already completed)
    private func retrievePassword() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Keys.biometricPassword,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    /// Delete stored password
    private func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Keys.biometricPassword
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum BiometricError: LocalizedError {
    case notAvailable
    case notEnabled
    case authenticationFailed
    case credentialsNotFound
    case encodingFailed
    case accessControlCreationFailed
    case keychainSaveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notEnabled:
            return "Biometric login is not enabled"
        case .authenticationFailed:
            return "Biometric authentication failed"
        case .credentialsNotFound:
            return "Stored credentials not found. Please log in with your password."
        case .encodingFailed:
            return "Failed to encode credentials"
        case .accessControlCreationFailed:
            return "Failed to create secure storage"
        case .keychainSaveFailed(let status):
            return "Failed to save credentials (error \(status))"
        }
    }
}
```

**Estimated time**: 2 hours

---

### Phase 2: Update LoginView

#### Session Start Instructions

1. Read this plan file (`docs/mobile/face-id-implementation-plan.md`)
2. Read `ios/BookVault/Views/LoginView.swift` - note the current structure:
   - How `@StateObject` or `@EnvironmentObject` is used for `AuthManager`
   - Where the login button and form fields are located
   - The current `login()` or submit handler method
3. Read `ios/BookVault/Services/AuthManager.swift` - note:
   - The `login(email:password:)` method signature
   - How success/failure is communicated (published properties, completion handlers, etc.)
4. Verify Phase 1 is complete (`BiometricAuthManager.swift` exists)

**Modify**: `ios/BookVault/Views/LoginView.swift`

#### Changes Required

1. Add `BiometricAuthManager` as `@StateObject`
2. Add Face ID button (conditionally shown)
3. Handle biometric authentication flow
4. Show "Enable Face ID" prompt after successful password login

```swift
// Add to LoginView.swift

@StateObject private var biometricManager = BiometricAuthManager.shared
@State private var showEnableBiometricPrompt = false

// Add Face ID button in body (before password field or as alternative)
if biometricManager.canUseBiometrics && biometricManager.isBiometricEnabledFor(email: email) {
    Button(action: { Task { await authenticateWithBiometric() } }) {
        HStack {
            Image(systemName: biometricManager.biometryType == .faceID ? "faceid" : "touchid")
            Text("Use \(biometricManager.biometryName)")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(10)
    }
    .disabled(authManager.isLoading)

    Text("or")
        .foregroundColor(.secondary)
        .padding(.vertical, 8)
}

// Add biometric authentication method
private func authenticateWithBiometric() async {
    do {
        let credentials = try await biometricManager.authenticateAndGetCredentials()
        await authManager.login(email: credentials.email, password: credentials.password)
    } catch {
        // Show error - user can fall back to password
        authManager.errorMessage = error.localizedDescription
    }
}

// Add prompt after successful login (in login success handler)
private func handleLoginSuccess(email: String, password: String) {
    if biometricManager.canUseBiometrics && !biometricManager.isBiometricEnabled {
        // Store temporarily for prompt
        pendingBiometricCredentials = (email, password)
        showEnableBiometricPrompt = true
    }
}

// Add alert modifier to body
.alert("Enable \(biometricManager.biometryName)?", isPresented: $showEnableBiometricPrompt) {
    Button("Enable") {
        if let credentials = pendingBiometricCredentials {
            try? biometricManager.enableBiometric(
                email: credentials.email,
                password: credentials.password
            )
        }
        pendingBiometricCredentials = nil
    }
    Button("Not Now", role: .cancel) {
        pendingBiometricCredentials = nil
    }
} message: {
    Text("Log in faster next time using \(biometricManager.biometryName)")
}
```

**Estimated time**: 1.5 hours

#### Wiring Note: LoginView ↔ AuthManager Communication

The biometric enable prompt requires knowing when login succeeds AND having access to the password. Two approaches:

**Option A (Recommended): Handle entirely in LoginView**

- LoginView already has `email` and `password` in state
- After calling `authManager.login()`, check `authManager.isAuthenticated`
- If true, show biometric enable prompt using the local state values
- No changes needed to AuthManager's public API

**Option B: Callback from AuthManager**

- Add `onLoginSuccess: ((String, String) -> Void)?` to AuthManager
- AuthManager calls this after successful login
- LoginView sets this callback in `.onAppear`
- More complex but cleaner separation

**This plan uses Option A** - Phase 2 handles the prompt logic entirely in LoginView by checking `authManager.isAuthenticated` after login completes.

---

### Phase 3: Update AuthManager (Minimal - Logout Only)

> **Note**: Since we're using Option A (LoginView handles biometric prompt), Phase 3 only needs to handle logout behavior. This phase is **optional** if you want biometrics to persist across logout.

#### Session Start Instructions

1. Read this plan file (`docs/mobile/face-id-implementation-plan.md`)
2. Read `ios/BookVault/Services/AuthManager.swift` - focus on the `logout()` method
3. Decide: Should logout clear biometric enrollment?
   - **Keep enabled** (recommended): User stays enrolled, just logs out
   - **Clear on logout**: More secure, user must re-enable after each logout
4. Verify Phases 1-2 are complete

**Modify**: `ios/BookVault/Services/AuthManager.swift`

#### Changes Required

1. ~~Add callback for successful login~~ (handled in LoginView via Option A)
2. (Optional) Clear biometric data on logout - depends on UX preference

```swift
// Add to AuthManager.swift

/// Called after successful login - used to trigger biometric enrollment prompt
var onLoginSuccess: ((String, String) -> Void)?

// In login() method, after successful authentication:
func login(email: String, password: String) async {
    // ... existing login code ...

    if success {
        // Notify for biometric enrollment opportunity
        onLoginSuccess?(email, password)
    }
}

// In logout() method (optional - decide on UX):
func logout() async {
    // ... existing logout code ...

    // Option A: Keep biometric enabled (user stays enrolled)
    // Option B: Clear biometric (more secure, user must re-enable)
    // BiometricAuthManager.shared.disableBiometric()
}
```

**Estimated time**: 30 minutes

---

### Phase 4: Settings Integration

#### Session Start Instructions

1. Read this plan file (`docs/mobile/face-id-implementation-plan.md`)
2. Check if `ios/BookVault/Views/SettingsView.swift` exists:
   - If yes: Read it and find where to add the biometric section
   - If no: Check where settings are currently handled (might be in `ProfileView.swift` or similar)
3. Read `ios/BookVault/Services/BiometricAuthManager.swift` to understand the public API
4. Verify Phases 1-3 are complete

**Modify**: `ios/BookVault/Views/SettingsView.swift` (or create if doesn't exist)

```swift
// Add biometric toggle in settings

struct BiometricSettingsSection: View {
    @StateObject private var biometricManager = BiometricAuthManager.shared
    @State private var showDisableConfirmation = false

    var body: some View {
        Section("Security") {
            if biometricManager.canUseBiometrics {
                Toggle(
                    "\(biometricManager.biometryName) Login",
                    isOn: Binding(
                        get: { biometricManager.isBiometricEnabled },
                        set: { newValue in
                            if !newValue {
                                showDisableConfirmation = true
                            }
                            // Enable is handled via login flow, not here
                        }
                    )
                )
                .disabled(!biometricManager.isBiometricEnabled) // Can only disable, not enable from settings

                if !biometricManager.isBiometricEnabled {
                    Text("Log in with your password to enable \(biometricManager.biometryName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(biometricManager.biometryName) not available")
                    .foregroundColor(.secondary)
            }
        }
        .alert("Disable \(biometricManager.biometryName)?", isPresented: $showDisableConfirmation) {
            Button("Disable", role: .destructive) {
                biometricManager.disableBiometric()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to enter your password to log in")
        }
    }
}
```

**Estimated time**: 45 minutes

---

### Phase 5: Info.plist Configuration

#### Session Start Instructions

1. Read this plan file (`docs/mobile/face-id-implementation-plan.md`)
2. Read `ios/BookVault/Info.plist` to see current structure
3. This phase can be done in parallel with Phase 6

**Modify**: `ios/BookVault/Info.plist`

Add Face ID usage description (required by App Store):

```xml
<key>NSFaceIDUsageDescription</key>
<string>Book Vault uses Face ID to securely log you in without entering your password.</string>
```

**Estimated time**: 5 minutes

---

### Phase 6: XcodeGen Update

#### Session Start Instructions

1. Read this plan file (`docs/mobile/face-id-implementation-plan.md`)
2. Read `ios/project.yml` to understand current structure and where dependencies are listed
3. This phase can be done in parallel with Phase 5
4. After modifying, run `cd ios && xcodegen generate` to regenerate the Xcode project

**Modify**: `ios/project.yml`

Add LocalAuthentication framework:

```yaml
targets:
  BookVault:
    # ... existing config ...
    settings:
      # ... existing settings ...
    dependencies:
      - framework: LocalAuthentication.framework
```

Then regenerate: `cd ios && xcodegen generate`

**Estimated time**: 10 minutes

---

## File Changes Summary

| File                                  | Action        | Lines Changed (est.) |
| ------------------------------------- | ------------- | -------------------- |
| `Services/BiometricAuthManager.swift` | **Create**    | ~200                 |
| `Views/LoginView.swift`               | Modify        | ~60                  |
| `Services/AuthManager.swift`          | Modify        | ~15                  |
| `Views/SettingsView.swift`            | Modify/Create | ~50                  |
| `Info.plist`                          | Modify        | ~3                   |
| `project.yml`                         | Modify        | ~2                   |

**Total new/modified lines**: ~330

---

## Testing

### Unit Tests

**Create**: `ios/BookVaultTests/BiometricAuthManagerTests.swift`

```swift
import XCTest
@testable import BookVault

class BiometricAuthManagerTests: XCTestCase {

    func testBiometryTypeDetection() {
        let manager = BiometricAuthManager.shared
        // Verify biometryType is detected (will be .none in simulator)
        XCTAssertNotNil(manager.biometryType)
    }

    func testEnableDisableBiometric() throws {
        let manager = BiometricAuthManager.shared

        // Initially disabled
        XCTAssertFalse(manager.isBiometricEnabled)

        // Enable (will fail in simulator without biometrics)
        // This test should use a mock keychain in real implementation

        // Disable
        manager.disableBiometric()
        XCTAssertFalse(manager.isBiometricEnabled)
    }

    func testBiometryName() {
        let manager = BiometricAuthManager.shared
        let name = manager.biometryName
        XCTAssertFalse(name.isEmpty)
    }
}
```

### Manual Test Scenarios

| Scenario                | Steps                        | Expected Result                             |
| ----------------------- | ---------------------------- | ------------------------------------------- |
| **First login**         | Login with password          | Prompt to enable Face ID appears            |
| **Enable Face ID**      | Tap "Enable" on prompt       | Face ID button appears on next login        |
| **Face ID login**       | Tap Face ID button           | Face ID prompt → successful login           |
| **Face ID cancel**      | Cancel Face ID prompt        | Returns to login form, can use password     |
| **Face ID fail**        | Fail Face ID 3 times         | Error shown, password form available        |
| **Disable in settings** | Toggle off in settings       | Confirmation → Face ID disabled             |
| **Re-enable**           | Login with password again    | Prompt appears again                        |
| **Different user**      | Login as different user      | Face ID prompt for new user                 |
| **Biometric change**    | Add new face in iOS settings | Stored password invalidated, must re-enable |

### Simulator Limitations

- Face ID/Touch ID can be simulated via **Features > Face ID > Enrolled** in Simulator menu
- Use **Features > Face ID > Matching Face/Non-matching Face** to test success/failure
- Keychain with biometric protection may behave differently in simulator

---

## Edge Cases & Error Handling

### Edge Cases to Handle

1. **Device doesn't support biometrics**: Hide Face ID option entirely
2. **Biometrics not enrolled**: Show message "Set up Face ID in Settings"
3. **User cancels Face ID**: Return to password form gracefully
4. **Face ID locked out**: After multiple failures, iOS locks biometrics temporarily
5. **Biometric data changed**: `.biometryCurrentSet` flag invalidates stored password
6. **Multiple accounts**: Only one account can have biometric enabled at a time
7. **Password changed on web**: Stored password becomes invalid → clear biometric, prompt re-enable

### Error Messages (User-Friendly)

| Error                 | Message                                                                       |
| --------------------- | ----------------------------------------------------------------------------- |
| Face ID not available | "Face ID is not available on this device"                                     |
| Face ID not enrolled  | "Set up Face ID in Settings to use this feature"                              |
| Authentication failed | "Face ID didn't recognize you. Please try again or use your password."        |
| Credentials not found | "Please log in with your password to re-enable Face ID"                       |
| Lockout               | "Face ID is temporarily locked. Please try again later or use your password." |

---

## Future Enhancements

### Post-Implementation Improvements

1. **Automatic Face ID on app launch**: If enabled, trigger Face ID automatically when app opens (while showing login screen)

2. **Biometric for sensitive actions**: Use Face ID to confirm:
   - Viewing account details
   - Deleting downloads
   - Changing settings

3. **Multiple account support**: Allow switching between accounts with separate biometric enrollment

4. **Passwordless migration**: If backend adds support, migrate to device-bound tokens (more secure than stored passwords)

---

## Dependencies

### Required

- iOS 13.0+ (LocalAuthentication framework)
- Device with Face ID or Touch ID

### Optional

- iOS 15.0+ for `.opticID` support (Vision Pro)

---

## Checklist

Before starting implementation:

- [ ] Review current `LoginView.swift` implementation
- [ ] Review current `AuthManager.swift` implementation
- [ ] Verify `SystemKeychain.swift` patterns
- [ ] Set up test device with Face ID enrolled
- [ ] Review Apple's [LocalAuthentication documentation](https://developer.apple.com/documentation/localauthentication)

During implementation:

- [ ] Create `BiometricAuthManager.swift`
- [ ] Add Face ID usage description to `Info.plist`
- [ ] Update `project.yml` with LocalAuthentication framework
- [ ] Run `xcodegen generate`
- [ ] Modify `LoginView.swift`
- [ ] Modify `AuthManager.swift`
- [ ] Add settings toggle
- [ ] Test on physical device
- [ ] Test simulator with enrolled Face ID

After implementation:

- [ ] Write unit tests
- [ ] Test all edge cases manually
- [ ] Test on device without biometrics
- [ ] Test biometric change scenario
- [ ] Update documentation

---

## References

- [Apple LocalAuthentication Documentation](https://developer.apple.com/documentation/localauthentication)
- [Keychain Services - Access Control](https://developer.apple.com/documentation/security/keychain_services/keychain_items/restricting_keychain_item_accessibility)
- [Human Interface Guidelines - Authentication](https://developer.apple.com/design/human-interface-guidelines/authentication)
- [WWDC: Secure Your App's Data](https://developer.apple.com/videos/play/wwdc2019/709/)
