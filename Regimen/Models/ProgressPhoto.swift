//
//  ProgressPhoto.swift
//  Regimen
//

import CoreGraphics
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
    /// until the user analyzes this specific photo.
    var skinScore: Double?

    /// Whole-face attributes the scan flagged, by
    /// `SkinAttribute.persistenceKey`. Empty both when nothing was flagged
    /// and when this photo has never been scanned -- `skinScore` is what
    /// distinguishes those.
    var skinAttributeKeys: [String]

    /// Storage path of the rendered highlight overlay, if the scan flagged
    /// anything. Nil for an unscanned photo *and* for a scan that found
    /// nothing worth drawing.
    var overlayPath: String?

    /// Normalized crop of the photo the scan ran on, which is what the
    /// overlay is positioned against. All four are set together with
    /// `overlayPath`.
    var faceRectX: Double?
    var faceRectY: Double?
    var faceRectWidth: Double?
    var faceRectHeight: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case timestamp
        case storagePath = "storage_path"
        case note
        case skinScore = "skin_score"
        case skinAttributeKeys = "skin_attributes"
        case overlayPath = "overlay_path"
        case faceRectX = "face_rect_x"
        case faceRectY = "face_rect_y"
        case faceRectWidth = "face_rect_width"
        case faceRectHeight = "face_rect_height"
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        timestamp: Date = .now,
        storagePath: String,
        note: String? = nil,
        skinScore: Double? = nil,
        skinAttributeKeys: [String] = [],
        overlayPath: String? = nil,
        faceRectX: Double? = nil,
        faceRectY: Double? = nil,
        faceRectWidth: Double? = nil,
        faceRectHeight: Double? = nil
    ) {
        self.id = id
        self.userID = userID
        self.timestamp = timestamp
        self.storagePath = storagePath
        self.note = note
        self.skinScore = skinScore
        self.skinAttributeKeys = skinAttributeKeys
        self.overlayPath = overlayPath
        self.faceRectX = faceRectX
        self.faceRectY = faceRectY
        self.faceRectWidth = faceRectWidth
        self.faceRectHeight = faceRectHeight
    }

    /// Rows written before `scan_persistence.sql` ran have no
    /// `skin_attributes` value at all, so this decodes as absent rather
    /// than failing the whole fetch.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        storagePath = try container.decode(String.self, forKey: .storagePath)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        skinScore = try container.decodeIfPresent(Double.self, forKey: .skinScore)
        skinAttributeKeys = try container.decodeIfPresent([String].self, forKey: .skinAttributeKeys) ?? []
        overlayPath = try container.decodeIfPresent(String.self, forKey: .overlayPath)
        faceRectX = try container.decodeIfPresent(Double.self, forKey: .faceRectX)
        faceRectY = try container.decodeIfPresent(Double.self, forKey: .faceRectY)
        faceRectWidth = try container.decodeIfPresent(Double.self, forKey: .faceRectWidth)
        faceRectHeight = try container.decodeIfPresent(Double.self, forKey: .faceRectHeight)
    }

    var skinAttributes: [SkinAttribute] {
        skinAttributeKeys.compactMap(SkinAttribute.init(persistenceKey:))
    }

    /// The stored crop, or nil if any component is missing -- a partially
    /// written rect would position the overlay somewhere arbitrary, which
    /// is worse than not drawing it.
    var faceRect: CGRect? {
        guard let faceRectX, let faceRectY, let faceRectWidth, let faceRectHeight else { return nil }
        return CGRect(x: faceRectX, y: faceRectY, width: faceRectWidth, height: faceRectHeight)
    }

    /// Whether this photo has a scan worth redisplaying without re-running
    /// the models.
    var hasStoredScan: Bool { skinScore != nil }
}
