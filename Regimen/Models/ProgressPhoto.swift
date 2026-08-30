//
//  ProgressPhoto.swift
//  Regimen
//

import Foundation

/// Maps 1:1 to the `progress_photos` table. Only metadata lives in Postgres
/// — `storagePath` points at the actual JPEG in the private
/// `progress-photos` Supabase Storage bucket (see `PhotoStorageService`),
/// keeping large binary blobs out of the database.
struct ProgressPhoto: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var timestamp: Date
    var storagePath: String
    var note: String?

    /// 0-100, set by the on-device skin scan (see `SkinScanService`) — nil
    /// until the user analyzes this specific photo. The scan's highlighted
    /// patches are deliberately not persisted: they're recomputed from the
    /// photo on demand, so only the one number that trends over time needs
    /// a column.
    var skinScore: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case timestamp
        case storagePath = "storage_path"
        case note
        case skinScore = "skin_score"
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        timestamp: Date = .now,
        storagePath: String,
        note: String? = nil,
        skinScore: Double? = nil
    ) {
        self.id = id
        self.userID = userID
        self.timestamp = timestamp
        self.storagePath = storagePath
        self.note = note
        self.skinScore = skinScore
    }
}
