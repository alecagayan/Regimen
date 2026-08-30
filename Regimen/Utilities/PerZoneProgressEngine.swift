//
//  PerZoneProgressEngine.swift
//  Regimen
//

import Foundation

/// Trends each face zone's flagged severity across every scanned photo,
/// using the `ZoneFinding` rows `AppData.scanPhoto` persists per scan.
/// Absence of a row for a given (photo, zone) genuinely means that scan
/// found nothing there -- `ZoneFinding.aggregate` only ever creates rows
/// for zones a scan actually flagged -- so it's read as a real zero, not
/// missing data.
enum PerZoneProgressEngine {
    struct ZoneProgress: Identifiable {
        let zone: FaceZone
        var id: FaceZone { zone }
        /// Severity (sum of flagged cells, all kinds) at the earliest and
        /// latest scan in the photo history.
        let earliestSeverity: Int
        let latestSeverity: Int
        var delta: Int { latestSeverity - earliestSeverity }
    }

    /// Needs at least two scanned photos to trend against -- same bar
    /// `ProgressTabView.scoredPhotos.count >= 2` already sets for the skin
    /// score chart.
    static func build(zoneFindings: [ZoneFinding], progressPhotos: [ProgressPhoto]) -> [ZoneProgress] {
        let scannedPhotos = progressPhotos
            .filter { $0.skinScore != nil }
            .sorted { $0.timestamp < $1.timestamp }
        guard scannedPhotos.count >= 2,
              let earliestPhoto = scannedPhotos.first,
              let latestPhoto = scannedPhotos.last
        else { return [] }

        let byPhoto = Dictionary(grouping: zoneFindings, by: \.progressPhotoID)

        func severity(for photo: ProgressPhoto, zone: FaceZone) -> Int {
            (byPhoto[photo.id] ?? [])
                .filter { $0.zone == zone }
                .reduce(0) { $0 + $1.cellCount }
        }

        return FaceZone.allCases.map { zone in
            ZoneProgress(
                zone: zone,
                earliestSeverity: severity(for: earliestPhoto, zone: zone),
                latestSeverity: severity(for: latestPhoto, zone: zone)
            )
        }
    }
}
