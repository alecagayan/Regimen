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
    /// Shown after a password-reset link is opened. Lives here rather than
    /// on the auth screens because the link arrives while signed out and
    /// then *signs the user in*, so by the time it's handled `RootView`
    /// has already swapped to the main app -- a sheet owned by the
    /// sign-in screen would be torn down mid-flow.
    @State private var showSetNewPassword = false

    var body: some View {
        Group {
            if auth.isLoading {
                loadingView
            } else if let session = auth.session {
                if let appData {
                    // Deliberately no notification prompt here. iOS grants
                    // exactly one chance to ask, ever, and asking the
                    // instant a session exists -- before a product has been
                    // added or a scan run -- spends it at the moment the
                    // user has least reason to say yes. A denial is then
                    // permanent short of a trip to Settings, which silently
                    // caps reorder and streak reminders for that install
                    // forever. It's asked for at the points where the value
                    // is already obvious instead: finishing a routine (see
                    // `RoutineView`) and switching reminders on in Settings.
                    ContentView()
                        .environment(appData)
                        .environment(\.signOut, signOut)
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
        // Recovery links have to be caught above the signed-in/signed-out
        // split, since opening one crosses it.
        .onOpenURL { url in
            Task {
                guard (try? await auth.completePasswordRecovery(from: url)) == true else { return }
                showSetNewPassword = true
            }
        }
        .sheet(isPresented: $showSetNewPassword) {
            SetNewPasswordView()
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
        // Wipe this account's on-disk snapshot and pending writes before
        // dropping the reference -- otherwise the next person to sign in on
        // this device would have the previous user's products and skin
        // scores sitting in Application Support.
        appData?.clearLocalData()
        try await auth.signOut()
        appData = nil
    }
}
