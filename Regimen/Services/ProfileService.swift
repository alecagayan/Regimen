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
}
