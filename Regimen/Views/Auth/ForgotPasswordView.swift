//
//  ForgotPasswordView.swift
//  Regimen
//

import SwiftUI

/// The way back into an account when the password is gone.
///
/// Sign-in is email and password with no third-party provider, so before
/// this screen existed a forgotten password meant a permanently lost
/// account -- every photo, scan and streak with it -- and the app offered
/// no way to ask anyone for help.
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    /// Prefilled from whatever was already typed on the sign-in screen, so
    /// nobody types their address twice.
    @State var email: String

    @State private var isSubmitting = false
    @State private var hasSent = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        email.contains("@") && !email.hasPrefix("@")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if hasSent {
                        sentState
                    } else {
                        formState
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var formState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AuthBranding(
                title: "Reset Password",
                subtitle: "We'll email you a link to set a new one."
            )

            AuthField(
                title: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.rowSubtitle)
                    .foregroundStyle(.red)
            }

            Button(action: submit) {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Reset Link")
                }
            }
            .buttonStyle(.primary)
            .disabled(!isValid || isSubmitting)
        }
    }

    /// Worded so it says the same thing whether or not the address has an
    /// account. Confirming that an address is registered would let anyone
    /// test addresses to find out who uses the app.
    private var sentState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(Color.brand)
                .padding(.top, Theme.Spacing.xl)

            Text("Check Your Email")
                .font(.screenTitle)

            Text("If an account exists for \(email), a reset link is on its way. It expires in an hour.")
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .buttonStyle(.primary)
                .padding(.top, Theme.Spacing.md)
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await AuthService.shared.sendPasswordReset(email: email)
                hasSent = true
            } catch {
                // Rate limiting is the realistic failure here, and it is
                // worth naming: "try again" with no reason reads as the
                // app being broken.
                errorMessage = "Couldn't send the email just now. Check the address and try again in a minute."
            }
        }
    }
}
