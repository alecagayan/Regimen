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

    static func updateScore(id: UUID, score: Double) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["skin_score": score])
            .eq("id", value: id)
            .execute()
    }

    /// Nil clears the note, which is why this takes `String?` rather than
    /// skipping the write on empty.
    static func updateNote(id: UUID, note: String?) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(["note": note])
            .eq("id", value: id)
            .execute()
    }

    /// Everything a finished scan leaves behind, written in one round trip
    /// (see `supabase/scan_persistence.sql`). Nil `overlayPath`/`faceRect`
    /// is a real value here, not "leave unchanged" -- a re-scan that finds
    /// nothing must clear the previous scan's overlay rather than leaving a
    /// stale one pointing at highlights that no longer exist.
    struct ScanUpdate: Encodable {
        let skinScore: Double
        let skinAttributes: [String]
        let overlayPath: String?
        let faceRectX: Double?
        let faceRectY: Double?
        let faceRectWidth: Double?
        let faceRectHeight: Double?

        enum CodingKeys: String, CodingKey {
            case skinScore = "skin_score"
            case skinAttributes = "skin_attributes"
            case overlayPath = "overlay_path"
            case faceRectX = "face_rect_x"
            case faceRectY = "face_rect_y"
            case faceRectWidth = "face_rect_width"
            case faceRectHeight = "face_rect_height"
        }
    }

    static func updateScan(id: UUID, update: ScanUpdate) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(update)
            .eq("id", value: id)
            .execute()
    }
}
