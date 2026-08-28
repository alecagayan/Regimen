//
//  CreateAccountView.swift
//  Regimen
//

import SwiftUI

struct CreateAccountView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var awaitingEmailConfirmation = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.contains("@")
            && password.count >= 6
            && password == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if awaitingEmailConfirmation {
                    confirmationPending
                } else {
                    AuthBranding(
                        title: "Create Your Account",
                        subtitle: "Track your routine, predict reorders, and see your progress — synced to your account."
                    )

                    VStack(spacing: Theme.Spacing.sm) {
                        AuthField(title: "Name", text: $name, textContentType: .name)
                        AuthField(title: "Email", text: $email, keyboardType: .emailAddress, textContentType: .emailAddress)
                        AuthField(title: "Password", text: $password, isSecure: true, textContentType: .newPassword)
                        AuthField(title: "Confirm Password", text: $confirmPassword, isSecure: true, textContentType: .newPassword)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create Account")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!isValid || isSubmitting)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var confirmationPending: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Color.brand.opacity(0.12)).frame(width: 88, height: 88)
                Image(systemName: "envelope.badge")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.brand)
            }
            Text("Check Your Email")
                .font(.display(22))
            Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let signedInImmediately = try await AuthService.shared.signUp(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email,
                    password: password
                )
                if !signedInImmediately {
                    awaitingEmailConfirmation = true
                }
                // If signed in immediately, AuthService's session listener
                // picks up the new session on its own — RootView reacts to
                // that, nothing more to do here.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
