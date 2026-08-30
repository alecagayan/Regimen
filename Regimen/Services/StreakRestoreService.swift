//
//  StreakRestoreService.swift
//  Regimen
//

import Foundation
import Supabase

enum StreakRestoreService {
    private static var table: String { "streak_restores" }

    static func fetchAll(userID: UUID) async throws -> [StreakRestore] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("restored_on", ascending: false)
            .execute()
            .value
    }

    static func insert(_ restore: StreakRestore) async throws {
        try await SupabaseManager.client
            .from(table)
            .insert(restore)
            .execute()
    }
}
