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
    /// True until the first *usable* auth state (restored session or none)
    /// arrives.
    private(set) var isLoading = true

    private let client = SupabaseManager.client

    private init() {
        Task { await observeAuthChanges() }
    }

    private func observeAuthChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            print("AuthService: \(event), userID \(session?.user.id.uuidString ?? "nil"), expired \(session?.isExpired ?? false)")
            // SupabaseManager enables emitLocalSessionAsInitialSession, so
            // this first event can be an on-disk session that's already
            // expired (stale from a previous launch, refresh token also
            // dead, whatever) rather than nil or a valid one. Publishing it
            // as-is would make every RLS-protected query authenticate as
            // nobody and silently come back empty. The SDK's own auto
            // token refresh will emit a follow-up event shortly (a
            // refreshed session, or nil if refresh genuinely fails) --
            // wait for that instead of the expired snapshot.
            if let session, session.isExpired {
                continue
            }
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

    /// Permanently deletes the signed-in user's account -- required for
    /// App Store approval (Guideline 5.1.1(v): any app that supports
    /// account creation must let the user delete it from within the app).
    /// Runs a `security definer` Postgres function (see
    /// `supabase/delete_account.sql`) rather than the client SDK directly,
    /// since deleting an `auth.users` row needs the service role key,
    /// which never belongs on-device. Every other table cascades from that
    /// row's deletion via its `on delete cascade` foreign key (see
    /// schema.sql) except Storage objects, which the function deletes
    /// itself before removing the row.
    func deleteAccount() async throws {
        try await client.rpc("delete_own_account").execute()
        try await client.auth.signOut()
    }
}
