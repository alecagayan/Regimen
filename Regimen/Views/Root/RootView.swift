//
//  RootView.swift
//  Regimen
//

import SwiftUI
import Supabase

private struct SignOutActionKey: EnvironmentKey {
    static let defaultValue: () async throws -> Void = {}
}

extension EnvironmentValues {
    /// Lets any descendant view (see `ProductsView`'s account button) trigger
    /// sign-out without needing a reference to `AuthService` or `RootView`.
    var signOut: () async throws -> Void {
        get { self[SignOutActionKey.self] }
        set { self[SignOutActionKey.self] = newValue }
    }
}

/// The single entry point below the app's `WindowGroup`. Gates the app
/// behind three states in order: loading the cached session, signed out
/// (auth screens), and signed in (main app, with a one-time onboarding
/// cover for a freshly created account).
struct RootView: View {
    @State private var auth = AuthService.shared
    @State private var appData: AppData?
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if auth.isLoading {
                loadingView
            } else if let session = auth.session {
                if let appData {
                    ContentView()
                        .environment(appData)
                        .environment(\.signOut, signOut)
                        .task {
                            await NotificationManager.shared.requestAuthorizationIfNeeded()
                        }
                        .fullScreenCover(isPresented: $showOnboarding) {
                            OnboardingView(onFinish: {
                                Task { await completeOnboarding() }
                            })
                        }
                } else {
                    loadingView
                        .task(id: session.user.id) {
                            await bootstrap(userID: session.user.id)
                        }
                }
            } else {
                AuthContainerView()
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ProgressView()
        }
    }

    private func bootstrap(userID: UUID) async {
        let data = AppData(userID: userID)
        await data.loadAll()

        // The `profiles` row is created by a database trigger the instant
        // `auth.signUp` succeeds, but that can race this fetch by a beat —
        // retry briefly rather than treating a not-yet-visible row as "no
        // onboarding needed".
        var fetchedProfile: Profile?
        for attempt in 0..<3 {
            if let profile = try? await ProfileService.fetch(userID: userID) {
                fetchedProfile = profile
                break
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }

        appData = data
        showOnboarding = !(fetchedProfile?.hasCompletedOnboarding ?? true)
    }

    private func completeOnboarding() async {
        showOnboarding = false
        guard let userID = auth.currentUserID else { return }
        try? await ProfileService.completeOnboarding(userID: userID)
    }

    private func signOut() async throws {
        try await auth.signOut()
        appData = nil
    }
}
