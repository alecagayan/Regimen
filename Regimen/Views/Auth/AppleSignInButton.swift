//
//  AppleSignInButton.swift
//  Regimen
//

import AuthenticationServices
import SwiftUI

/// Sign in with Apple, shared by the sign-in and create-account screens.
///
/// Worth having even though Guideline 4.8 doesn't compel it (that only
/// bites when you offer third-party social logins, and this app offers
/// none): it's the expected default on iOS, and it sidesteps the password
/// problem entirely for anyone who uses it -- no password to forget, so no
/// reset flow to need.
struct AppleSignInButton: View {
    /// Surfaced by the parent so the failure reads in the same place as an
    /// email/password failure, rather than in a second style of alert.
    @Binding var errorMessage: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            AuthService.shared.prepareAppleRequest(request)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                Task {
                    do {
                        try await AuthService.shared.signInWithApple(authorization)
                        // The session listener updates state; RootView
                        // reacts on its own.
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                // Cancelling is not an error worth shouting about -- the
                // user closed the sheet on purpose.
                guard (error as? ASAuthorizationError)?.code != .canceled else { return }
                errorMessage = "Couldn't sign in with Apple. Please try again."
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(Capsule())
    }
}

/// A labelled rule between the Apple button and the email form, so the two
/// read as alternatives rather than a sequence of steps.
struct AuthDivider: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Rectangle().fill(Color.subtleBorder).frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color.subtleBorder).frame(height: 1)
        }
    }
}
