//
//  SignInView.swift
//  Regimen
//

import SwiftUI

struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var isValid: Bool {
        email.contains("@") && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                AuthBranding(title: "Welcome Back", subtitle: "Sign in to pick up where you left off.")

                VStack(spacing: Theme.Spacing.sm) {
                    AuthField(title: "Email", text: $email, keyboardType: .emailAddress, textContentType: .emailAddress)
                    AuthField(title: "Password", text: $password, isSecure: true, textContentType: .password)
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
                        Text("Sign In")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!isValid || isSubmitting)
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await AuthService.shared.signIn(email: email, password: password)
                // AuthService's session listener updates state; RootView
                // reacts automatically.
            } catch {
                errorMessage = "Incorrect email or password."
            }
        }
    }
}
