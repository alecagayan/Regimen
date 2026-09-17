//
//  SetNewPasswordView.swift
//  Regimen
//

import SwiftUI

/// Where the link in a password-reset email lands.
///
/// Without this the reset flow stopped halfway: the email went out, the
/// link opened Supabase's own hosted page, and the user never got back
/// into the app with a password they could use. Opening the link now
/// exchanges its one-time token for a short-lived session (see
/// `AuthService.completePasswordRecovery`), which is what lets this screen
/// set a new password without asking for the old one.
struct SetNewPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// Matches what `CreateAccountView` enforces, so the rule doesn't
    /// change depending on which door you came in through.
    private var isValid: Bool {
        password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    AuthBranding(
                        title: "Set a New Password",
                        subtitle: "Pick something you'll remember. You're signed in already."
                    )

                    VStack(spacing: Theme.Spacing.sm) {
                        AuthField(
                            title: "New Password",
                            text: $password,
                            isSecure: true,
                            textContentType: .newPassword
                        )
                        AuthField(
                            title: "Confirm Password",
                            text: $confirmPassword,
                            isSecure: true,
                            textContentType: .newPassword
                        )
                    }

                    // Stated up front rather than only after a rejected
                    // attempt, so nobody discovers the rule by failing it.
                    if !password.isEmpty && password.count < 8 {
                        Text("At least 8 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !confirmPassword.isEmpty && password != confirmPassword {
                        Text("Those don't match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.rowSubtitle)
                            .foregroundStyle(.red)
                    }

                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save Password")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!isValid || isSubmitting)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await AuthService.shared.setPassword(password)
                dismiss()
            } catch {
                errorMessage = "Couldn't save that password. The reset link may have expired."
            }
        }
    }
}
