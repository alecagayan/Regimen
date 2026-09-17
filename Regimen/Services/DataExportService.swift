//
//  DataExportService.swift
//  Regimen
//

import Foundation
import os

/// Writes everything the account holds to a JSON file the user can keep.
///
/// Two reasons it earns its place: it's the honest answer to "is my data
/// actually mine", which matters for an app storing photos and skin scores,
/// and it's what makes the App Privacy questionnaire's data-portability
/// answers true rather than aspirational.
///
/// Photo *files* are not included -- they live in Storage as JPEGs and
/// would dominate the file size -- but `progressPhotos` now carries a
/// signed URL for each one so the export is actually actionable. Without
/// that it listed storage paths that stop resolving the moment the account
/// is deleted, which is precisely when someone would need them.
enum DataExportService {
    struct Export: Encodable {
        let exportedAt: Date
        /// The onboarding answers: skin type, sensitivity, experience,
        /// preferred routine length. Was missing, which made the export
        /// incomplete in the one category a user is most likely to think
        /// of as "my profile".
        let skinProfile: SkinProfile?
        let products: [Product]
        let usageLogs: [UsageLog]
        let progressPhotos: [ProgressPhoto]
        /// Time-limited download links for the photos, keyed by storage
        /// path. Signed URLs expire, so the export states when.
        let photoDownloads: [String: String]
        let photoDownloadsExpireAt: Date?
        let zoneFindings: [ZoneFinding]
        let streakRestores: [StreakRestore]
        let reactions: [SkinReaction]
        let empties: [ProductEmpty]
    }

    /// Returns a file URL ready to hand to a share sheet, or nil if writing
    /// it failed.
    static func write(_ export: Export) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(export)
            let name = "regimen-export-\(Date.now.formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.data.error("export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
