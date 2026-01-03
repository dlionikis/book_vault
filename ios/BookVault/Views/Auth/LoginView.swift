//
//  LoginView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var biometricManager = BiometricAuthManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var enableBiometricOnLogin = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email
        case password
    }

    var body: some View {
        NavigationView {
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

                // Face ID button (shown if enabled for this email or no email entered yet)
                if biometricManager.canUseBiometrics && biometricManager.isBiometricEnabled {
                    VStack(spacing: 12) {
                        Button(action: { Task { await authenticateWithBiometric() } }) {
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
                    // Email field
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
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
                    .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                    .padding(.top, 8)
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
            .navigationBarHidden(true)
        }
    }

    // MARK: - Private Methods

    private func login() {
        // Dismiss keyboard
        focusedField = nil

        // Capture values before async call
        let loginEmail = email
        let loginPassword = password
        let shouldEnableBiometric = enableBiometricOnLogin

        // Perform login
        Task {
            await authManager.login(email: loginEmail, password: loginPassword)

            // If login succeeded and user opted to enable biometrics, do it now
            if authManager.isAuthenticated && shouldEnableBiometric {
                do {
                    try biometricManager.enableBiometric(email: loginEmail, password: loginPassword)
                } catch {
                    // Silently fail - user can enable later in settings
                }
            }
        }
    }

    private func authenticateWithBiometric() async {
        do {
            let credentials = try await biometricManager.authenticateAndGetCredentials()
            await authManager.login(email: credentials.email, password: credentials.password)
        } catch {
            // Show error - user can fall back to password
            authManager.errorMessage = error.localizedDescription
        }
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
