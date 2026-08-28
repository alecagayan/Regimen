//
//  AuthContainerView.swift
//  Regimen
//

import SwiftUI

private enum AuthMode: CaseIterable, Identifiable, Hashable {
    case signIn
    case createAccount

    var id: Self { self }

    var label: String {
        switch self {
        case .signIn: "Sign In"
        case .createAccount: "Create Account"
        }
    }
}

/// The signed-out root: a Sign In / Create Account switch over the matching
/// form. Shown whenever `AuthService` has no active session.
struct AuthContainerView: View {
    @State private var mode: AuthMode = .createAccount

    var body: some View {
        VStack(spacing: 0) {
            PillToggle(selection: $mode, title: \.label)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)

            switch mode {
            case .signIn:
                SignInView()
            case .createAccount:
                CreateAccountView()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}
