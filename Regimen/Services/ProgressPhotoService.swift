//
//  ProgressPhotoService.swift
//  Regimen
//

import Foundation
import Supabase

enum ProgressPhotoService {
    private static var table: String { "progress_photos" }

    static func fetchAll(userID: UUID) async throws -> [ProgressPhoto] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("timestamp", ascending: false)
            .execute()
            .value
    }

    static func insert(_ photo: ProgressPhoto) async throws {
        try await SupabaseManager.client
            .from(table)
            .insert(photo)
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
