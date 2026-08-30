//
//  ProfileService.swift
//  Regimen
//

import Foundation
import Supabase

enum ProfileService {
    private static var table: String { "profiles" }

    static func fetch(userID: UUID) async throws -> Profile {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    static func completeOnboarding(userID: UUID) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["has_completed_onboarding": true])
            .eq("id", value: userID)
            .execute()
    }

    static func updateName(userID: UUID, name: String) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["name": name])
            .eq("id", value: userID)
            .execute()
    }

    static func setPremium(userID: UUID, isPremium: Bool) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["is_premium": isPremium])
            .eq("id", value: userID)
            .execute()
    }

    static func markFreeScanUsed(userID: UUID) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["has_used_free_scan": true])
            .eq("id", value: userID)
            .execute()
    }

    static func setPurchasedRestoreCredits(userID: UUID, count: Int) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["purchased_restore_credits": count])
            .eq("id", value: userID)
            .execute()
    }
}
