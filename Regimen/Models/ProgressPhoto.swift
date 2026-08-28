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

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case timestamp
        case storagePath = "storage_path"
        case note
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        timestamp: Date = .now,
        storagePath: String,
        note: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.timestamp = timestamp
        self.storagePath = storagePath
        self.note = note
    }
}
