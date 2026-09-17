//
//  AuthService.swift
//  Regimen
//

import AuthenticationServices
import CryptoKit
import Foundation
import Supabase
import os

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
            AppLog.auth.debug("auth state: \(String(describing: event), privacy: .public), userID \(session?.user.id.uuidString ?? "nil", privacy: .private), expired \(session?.isExpired ?? false, privacy: .public)")
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

    // MARK: - Sign in with Apple

    /// The raw nonce for the in-flight Apple request.
    ///
    /// Apple signs the SHA-256 *hash* of a nonce into the identity token,
    /// and Supabase verifies it against the raw value. Holding it here
    /// between building the request and handling the credential is what
    /// makes the token replay-proof: without it, a token captured from one
    /// sign-in could be presented again.
    private var appleNonce: String?

    /// Configures an Apple sign-in request, stashing the nonce it needs.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Exchanges a completed Apple credential for a Supabase session.
    ///
    /// Apple returns the user's name exactly once, on the very first
    /// authorization, and never again. If it isn't captured here it is
    /// gone for good, so it goes onto the profile in the same step.
    func signInWithApple(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthError.missingAppleToken
        }
        guard let nonce = appleNonce else {
            throw AuthError.missingAppleNonce
        }
        appleNonce = nil

        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )

        let names = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        guard !names.isEmpty, let userID = currentUserID else { return }
        // Best effort: a failure here costs a display name, not the
        // session the user just successfully created.
        try? await ProfileService.updateName(userID: userID, name: names)
    }

    enum AuthError: LocalizedError {
        case missingAppleToken
        case missingAppleNonce

        var errorDescription: String? {
            switch self {
            case .missingAppleToken: "Apple didn't return a usable sign-in token."
            case .missingAppleNonce: "That sign-in attempt expired. Please try again."
            }
        }
    }

    /// A cryptographically random nonce, in the character set Apple accepts.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            // Reject values that would bias the modulo, rather than
            // folding them in and skewing the distribution.
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Sends a password-reset email.
    ///
    /// Auth here is email and password with no third-party provider, so
    /// without this a forgotten password locked a user out of their own
    /// photos and history permanently, with no route back and no support
    /// channel to ask for one.
    ///
    /// Deliberately does not report whether the address is registered.
    /// Supabase returns success either way and the UI says the same thing
    /// either way, because an endpoint that distinguishes them is an
    /// account-enumeration oracle: anyone could test addresses against it
    /// to learn who uses a skincare app.
    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: AppDeepLink.passwordReset)
    }

    /// Turns the link from a reset email into a usable session.
    ///
    /// Supabase's recovery link carries a one-time token. Exchanging it
    /// signs the user in just long enough to set a new password -- which
    /// is why `setPassword` below can follow it without asking for the old
    /// one they have, by definition, forgotten.
    @discardableResult
    func completePasswordRecovery(from url: URL) async throws -> Bool {
        guard url.scheme == AppDeepLink.scheme, url.host() == "reset-password" else { return false }
        try await client.auth.session(from: url)
        return true
    }

    func setPassword(_ password: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: password))
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
