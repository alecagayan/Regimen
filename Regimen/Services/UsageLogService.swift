//
//  UsageLogService.swift
//  Regimen
//

import Foundation
import Supabase

enum UsageLogService {
    private static var table: String { "usage_logs" }

    static func fetchAll(userID: UUID) async throws -> [UsageLog] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("timestamp")
            .execute()
            .value
    }

    static func insert(_ log: UsageLog) async throws {
        try await SupabaseManager.client
            .from(table)
            .insert(log)
            .execute()
    }

    static func delete(id: UUID) async throws {
        try await SupabaseManager.client
            .from(table)
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
