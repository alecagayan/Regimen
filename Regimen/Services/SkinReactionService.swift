//
//  SkinReactionService.swift
//  Regimen
//

import Foundation
import Supabase

enum SkinReactionService {
    private static var table: String { "skin_reactions" }

    static func fetchAll(userID: UUID) async throws -> [SkinReaction] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("occurred_on", ascending: false)
            .execute()
            .value
    }

    /// Upsert on (user_id, occurred_on): marking the same day twice should
    /// correct the entry, not stack a second one. The table's unique
    /// constraint is what makes this safe.
    static func save(_ reaction: SkinReaction) async throws {
        try await SupabaseManager.client
            .from(table)
            .upsert(reaction, onConflict: "user_id,occurred_on")
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

enum ProductEmptyService {
    private static var table: String { "product_empties" }

    static func fetchAll(userID: UUID) async throws -> [ProductEmpty] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("finished_on", ascending: false)
            .execute()
            .value
    }

    static func insert(_ empty: ProductEmpty) async throws {
        try await SupabaseManager.client
            .from(table)
            .insert(empty)
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
