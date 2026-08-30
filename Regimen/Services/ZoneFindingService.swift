//
//  ZoneFindingService.swift
//  Regimen
//

import Foundation
import Supabase

enum ZoneFindingService {
    private static var table: String { "zone_findings" }

    static func fetchAll(userID: UUID) async throws -> [ZoneFinding] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value
    }

    /// Overwrites one photo's rows with a fresh set -- a re-scan should
    /// replace what was found, not pile duplicate rows on top of it.
    static func replace(forPhoto photoID: UUID, with findings: [ZoneFinding]) async throws {
        try await SupabaseManager.client
            .from(table)
            .delete()
            .eq("progress_photo_id", value: photoID)
            .execute()
        guard !findings.isEmpty else { return }
        try await SupabaseManager.client
            .from(table)
            .insert(findings)
            .execute()
    }
}
