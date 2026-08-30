//
//  ZoneFinding.swift
//  Regimen
//

import Foundation

/// Maps 1:1 to the `zone_findings` table. One row per (photo, zone, kind)
/// a scan actually flagged -- persists what `SkinScanService.findings(in:)`
/// computes so `PerZoneProgressEngine` has scan history to trend against,
/// rather than only ever seeing the one photo currently being viewed (the
/// overlay/findings themselves stay unpersisted and are recomputed fresh
/// per view, same as before -- only these per-zone counts are saved).
struct ZoneFinding: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var progressPhotoID: UUID
    var zone: FaceZone
    var kind: FindingKind
    /// Distinct flagged regions of this kind in this zone.
    var findingCount: Int
    /// Sum of those regions' cell counts -- a rough severity/size proxy.
    var cellCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case progressPhotoID = "progress_photo_id"
        case zone
        case kind
        case findingCount = "finding_count"
        case cellCount = "cell_count"
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        progressPhotoID: UUID,
        zone: FaceZone,
        kind: FindingKind,
        findingCount: Int,
        cellCount: Int
    ) {
        self.id = id
        self.userID = userID
        self.progressPhotoID = progressPhotoID
        self.zone = zone
        self.kind = kind
        self.findingCount = findingCount
        self.cellCount = cellCount
    }

    /// Collapses a scan's raw `SkinFinding`s (one per contiguous flagged
    /// region) into one row per (zone, kind) actually present.
    static func aggregate(from findings: [SkinFinding], userID: UUID, progressPhotoID: UUID) -> [ZoneFinding] {
        let grouped = Dictionary(grouping: findings) { ZoneKindKey(zone: $0.zone, kind: $0.kind) }
        return grouped.map { key, group in
            ZoneFinding(
                userID: userID,
                progressPhotoID: progressPhotoID,
                zone: key.zone,
                kind: key.kind,
                findingCount: group.count,
                cellCount: group.reduce(0) { $0 + $1.cellCount }
            )
        }
    }

    private struct ZoneKindKey: Hashable {
        let zone: FaceZone
        let kind: FindingKind
    }
}
