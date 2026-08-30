//
//  SupabaseManager.swift
//  Regimen
//

import Foundation
import Supabase

enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(
            auth: .init(
                // Default false (legacy) makes the very first
                // authStateChanges event wait on a network-dependent
                // refresh of the on-disk session before emitting anything.
                // On a cold launch with no network yet, or an expired
                // refresh token, that emission can end up not reflecting
                // the real signed-in session at all -- AuthService then
                // bootstraps AppData with a session whose access token
                // doesn't authenticate, every RLS-protected query silently
                // returns zero rows instead of an error, and the Cabinet
                // (and everything else) looks empty despite real data
                // existing. See AuthService.observeAuthChanges for the
                // matching `session.isExpired` check the SDK's own warning
                // says this flag requires.
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
