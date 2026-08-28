//
//  AuthService.swift
//  Regimen
//

import Foundation
import Supabase

/// Wraps Supabase's `auth` client and republishes the current session as
/// `@Observable` state. `authStateChanges` always emits an `.initialSession`
/// event as soon as you start listening, so a single long-running task here
/// both restores whatever session is cached on disk at launch and keeps
/// `session` in sync afterward (sign in, sign out, token refresh) — no
/// separate "restore" step needed.
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var session: Session?
    /// True until the first auth state (restored session or none) arrives.
    private(set) var isLoading = true

    private let client = SupabaseManager.client

    private init() {
        Task { await observeAuthChanges() }
    }

    private func observeAuthChanges() async {
        for await (_, session) in client.auth.authStateChanges {
            self.session = session
            isLoading = false
        }
    }

    var currentUserID: UUID? { session?.user.id }

    /// Returns `true` if signup produced an active session immediately.
    /// If the Supabase project has "Confirm email" enabled, `signUp`
    /// succeeds but returns no session until the user clicks the emailed
    /// confirmation link — the caller uses this to show the right message.
    @discardableResult
    func signUp(name: String, email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["name": .string(name)]
        )
        return response.session != nil
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
