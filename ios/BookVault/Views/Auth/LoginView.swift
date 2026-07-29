//
//  LoginView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    @State private var username = ""
    @State private var password = ""
    @State private var enableBiometricOnLogin = false
    @FocusState private var focusedField: Field?

    enum Field {
        case username
        case password
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Logo and title
            VStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("BookVault")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your Personal Audiobook Library")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)

            // Offline banner - shown when there is no connectivity so the
            // user understands why login may not work and can go offline.
            if !networkMonitor.isConnected {
                Label("No internet connection", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }

            // Face ID button (shown if enabled for this username or no username entered yet)
            if biometricManager.canUseBiometrics && biometricManager.isBiometricEnabled {
                VStack(spacing: 12) {
                    Button {
                        Task { await authenticateWithBiometric() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: biometricManager.biometryType == .faceID ? "faceid" : "touchid")
                                .font(.title2)
                            Text("Use \(biometricManager.biometryName)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authManager.isLoading)

                    Text("or sign in with password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }

            // Login form
            VStack(spacing: 16) {
                // Username field
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }

                // Password field
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        login()
                    }

                // Enable Face ID toggle (only shown if device supports biometrics and not already enabled)
                if biometricManager.canUseBiometrics && !biometricManager.isBiometricEnabled {
                    Toggle(isOn: $enableBiometricOnLogin) {
                        HStack(spacing: 6) {
                            Image(systemName: biometricManager.biometryType == .faceID ? "faceid" : "touchid")
                            Text("Enable \(biometricManager.biometryName)")
                        }
                        .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .padding(.top, 4)
                }

                // Error message
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Login button
                Button(action: login) {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Log In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || authManager.isLoading)
                .padding(.top, 8)

                // Continue Offline - escape hatch when there's no connectivity
                // but a prior session/identity exists on this device. Gated by
                // biometrics (when enrolled) so it is not an auth bypass.
                if !networkMonitor.isConnected,
                   authManager.hasRestorableSession || biometricManager.isBiometricEnabled {
                    Button {
                        Task { await continueOffline() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                            Text("Continue Offline")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(authManager.isLoading)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            #if DEBUG
            // Development hint - only shown in Debug builds
            VStack(spacing: 4) {
                Text("Development Credentials")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("test@example.com / password123")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
            #endif
        }
    }

    // MARK: - Private Methods

    private func login() {
        // Dismiss keyboard
        focusedField = nil

        // Short-circuit when offline: firing the request would hang on the
        // network timeout with only a spinner. Fail fast and point the user at
        // the offline option instead.
        guard networkMonitor.isConnected else {
            authManager.errorMessage = "You're offline. Check your connection, or continue offline."
            return
        }

        // Capture values before async call
        let loginUsername = username
        let loginPassword = password
        let shouldEnableBiometric = enableBiometricOnLogin

        // Perform login
        Task {
            await authManager.login(username: loginUsername, password: loginPassword)

            // If login succeeded and user opted to enable biometrics, do it now
            if authManager.isAuthenticated && shouldEnableBiometric {
                do {
                    try biometricManager.enableBiometric(username: loginUsername, password: loginPassword)
                } catch {
                    // Silently fail - user can enable later in settings
                }
            }
        }
    }

    private func authenticateWithBiometric() async {
        do {
            let credentials = try await biometricManager.authenticateAndGetCredentials()
            await authManager.login(username: credentials.username, password: credentials.password)
        } catch {
            // Show error - user can fall back to password
            authManager.errorMessage = error.localizedDescription
        }
    }

    /// Enter offline mode from the login screen. Requires a biometric check when
    /// biometrics are enrolled, so a stranger cannot open a previous user's
    /// downloaded content. Falls back to the cached session identity otherwise.
    private func continueOffline() async {
        if biometricManager.canUseBiometrics, biometricManager.isBiometricEnabled {
            do {
                _ = try await biometricManager.authenticateAndGetCredentials()
            } catch {
                authManager.errorMessage = "Biometric verification failed. Try again to continue offline."
                return
            }
        }
        authManager.enterOfflineMode()
    }
}

// MARK: - Previews

#Preview("Default") {
    LoginView()
}

#Preview("Dark Mode") {
    LoginView()
        .preferredColorScheme(.dark)
}
