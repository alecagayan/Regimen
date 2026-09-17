//
//  LocalCache.swift
//  Regimen
//

import Foundation
import os

/// An on-disk snapshot of everything `AppData` loads, so the app has
/// something to show before (or instead of) a successful network fetch.
///
/// Supabase remains the only source of truth -- this is a read cache, never
/// authoritative, and every successful `loadAll` overwrites it wholesale.
/// What it buys is that opening the app on a plane, on a subway, or on
/// hotel wifi shows the user's routine instead of an empty screen, which
/// for a daily-habit app is the difference between a kept streak and a
/// broken one.
///
/// Writes are handled separately by `PendingWriteQueue` -- a cache alone
/// would let a check-off *look* saved and then vanish on the next fetch.
struct CachedSnapshot: Codable, Sendable {
    var products: [Product]
    var usageLogs: [UsageLog]
    var progressPhotos: [ProgressPhoto]
    var zoneFindings: [ZoneFinding]
    var streakRestores: [StreakRestore]
    var reactions: [SkinReaction]
    var empties: [ProductEmpty]
    var isPremium: Bool
    var hasUsedFreeScan: Bool
    var purchasedRestoreCredits: Int
    var savedAt: Date

    init(
        products: [Product],
        usageLogs: [UsageLog],
        progressPhotos: [ProgressPhoto],
        zoneFindings: [ZoneFinding],
        streakRestores: [StreakRestore],
        reactions: [SkinReaction],
        empties: [ProductEmpty],
        isPremium: Bool,
        hasUsedFreeScan: Bool,
        purchasedRestoreCredits: Int,
        savedAt: Date
    ) {
        self.products = products
        self.usageLogs = usageLogs
        self.progressPhotos = progressPhotos
        self.zoneFindings = zoneFindings
        self.streakRestores = streakRestores
        self.reactions = reactions
        self.empties = empties
        self.isPremium = isPremium
        self.hasUsedFreeScan = hasUsedFreeScan
        self.purchasedRestoreCredits = purchasedRestoreCredits
        self.savedAt = savedAt
    }

    /// Collections added after a release decode as empty rather than
    /// failing the whole snapshot. Without this, every upgrade would throw
    /// away the previous version's cache and leave the first launch after
    /// an update with nothing to show offline.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = try container.decodeIfPresent([Product].self, forKey: .products) ?? []
        usageLogs = try container.decodeIfPresent([UsageLog].self, forKey: .usageLogs) ?? []
        progressPhotos = try container.decodeIfPresent([ProgressPhoto].self, forKey: .progressPhotos) ?? []
        zoneFindings = try container.decodeIfPresent([ZoneFinding].self, forKey: .zoneFindings) ?? []
        streakRestores = try container.decodeIfPresent([StreakRestore].self, forKey: .streakRestores) ?? []
        reactions = try container.decodeIfPresent([SkinReaction].self, forKey: .reactions) ?? []
        empties = try container.decodeIfPresent([ProductEmpty].self, forKey: .empties) ?? []
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        hasUsedFreeScan = try container.decodeIfPresent(Bool.self, forKey: .hasUsedFreeScan) ?? false
        purchasedRestoreCredits = try container.decodeIfPresent(Int.self, forKey: .purchasedRestoreCredits) ?? 0
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
    }
}

enum LocalCache {
    /// Application Support rather than Caches: the system may purge Caches
    /// under disk pressure, and a cache that disappears exactly when the
    /// user is offline is worse than none. Excluded from backups instead,
    /// since every byte is re-fetchable.
    private static func url(for userID: UUID) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Cache", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("snapshot-\(userID.uuidString).json")
    }

    static func load(userID: UUID) -> CachedSnapshot? {
        do {
            let url = try url(for: userID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CachedSnapshot.self, from: data)
        } catch {
            // A snapshot written by an older build whose models have since
            // changed shape will fail to decode. That's expected and
            // harmless -- drop it and fetch fresh.
            AppLog.sync.debug("cache load failed, ignoring: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `async` and deliberately not actor-isolated, so awaiting it from
    /// `AppData` (which is `@MainActor`) runs the encode and the file write
    /// on the cooperative pool instead of the main thread. Checking off a
    /// product saves the cache, and a user with a year of history has
    /// thousands of usage logs -- encoding that synchronously on every tap
    /// would be felt.
    static func save(_ snapshot: CachedSnapshot, userID: UUID) async {
        do {
            var url = try url(for: userID)
            let data = try JSONEncoder().encode(snapshot)
            // Complete protection: this holds the user's product list,
            // photo metadata and skin scores, so it should be unreadable
            // while the device is locked.
            try data.write(to: url, options: [.atomic, .completeFileProtection])

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            AppLog.sync.error("cache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called on sign-out -- leaving one account's data on disk for the
    /// next person to sign in on this device would be a real leak.
    static func clear(userID: UUID) {
        guard let url = try? url(for: userID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
