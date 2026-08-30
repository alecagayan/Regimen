//
//  AppData.swift
//  Regimen
//

import Foundation
import UIKit

/// Single in-memory source of truth for the signed-in user's products,
/// usage logs, and progress photos, loaded from Supabase once after sign-in
/// and mutated optimistically (update local state immediately, write to
/// Supabase in the background) so the UI feels instant.
///
/// This deliberately isn't a bidirectional offline sync engine — there's no
/// local cache, queue of pending writes, or conflict resolution. Supabase
/// Postgres is the only source of truth; if a write fails the local change
/// can drift from the server until the next `loadAll()`. That's a real
/// trade-off (no offline support), but a correct offline-first sync layer
/// is a much larger project than this app needs right now, and "the same
/// account works across devices" doesn't itself require one.
@MainActor
@Observable
final class AppData {
    private(set) var products: [Product] = []
    private(set) var usageLogs: [UsageLog] = []
    private(set) var progressPhotos: [ProgressPhoto] = []
    /// Per-zone scan history -- see `ZoneFinding` and `PerZoneProgressEngine`.
    private(set) var zoneFindings: [ZoneFinding] = []
    /// Days bridged by a premium streak restore -- see `StreakRestore`.
    private(set) var streakRestores: [StreakRestore] = []
    /// storagePath -> a signed URL valid for the lifetime set in
    /// `PhotoStorageService`. Refreshed on every `loadAll()`.
    private(set) var signedPhotoURLs: [String: URL] = [:]
    private(set) var isLoading = false
    /// Set when `addPhoto` fails, so the UI can actually show *something*
    /// instead of the upload silently doing nothing — which is exactly what
    /// swallowing the error with `try?` used to do here.
    var photoUploadErrorMessage: String?
    /// Gates every premium feature -- see `Profile.isPremium`.
    private(set) var isPremium = false

    let userID: UUID

    init(userID: UUID) {
        self.userID = userID
        SubscriptionService.shared.onEntitlementChanged = { [weak self] in
            await self?.refreshEntitlement()
        }
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        async let productsResult = fetchLogging(label: "products") { try await ProductService.fetchAll(userID: self.userID) }
        async let logsResult = fetchLogging(label: "usage logs") { try await UsageLogService.fetchAll(userID: self.userID) }
        async let photosResult = fetchLogging(label: "progress photos") { try await ProgressPhotoService.fetchAll(userID: self.userID) }
        async let profileResult = fetchLogging(label: "profile") { try await ProfileService.fetch(userID: self.userID) }
        async let zoneFindingsResult = fetchLogging(label: "zone findings") { try await ZoneFindingService.fetchAll(userID: self.userID) }
        async let restoresResult = fetchLogging(label: "streak restores") { try await StreakRestoreService.fetchAll(userID: self.userID) }

        products = await productsResult ?? []
        usageLogs = await logsResult ?? []
        progressPhotos = await photosResult ?? []
        isPremium = await profileResult?.isPremium ?? isPremium
        zoneFindings = await zoneFindingsResult ?? []
        streakRestores = await restoresResult ?? []

        await refreshSignedPhotoURLs()
        refreshAllNotifications()
        syncWidgetData()
    }

    /// Latest scored photo's score, oldest-to-newest tiebreak matching
    /// `ProgressTabView.scoredPhotos` -- the one number the widget shows
    /// alongside the streak.
    private var latestSkinScore: Double? {
        progressPhotos
            .filter { $0.skinScore != nil }
            .max { $0.timestamp < $1.timestamp }?
            .skinScore
    }

    private func syncWidgetData() {
        let streak = StreakCalculator.compute(from: usageLogs, restores: streakRestores).currentStreak
        WidgetDataStore.write(streak: streak, latestScore: latestSkinScore, isPremium: isPremium)
    }

    /// `try?` on each of loadAll's three fetches used to discard the actual
    /// error entirely -- any real failure (RLS silently returning zero
    /// rows for an unauthenticated request, a network error, a decoding
    /// mismatch) looked identical to "this user genuinely has no data",
    /// with nothing in the console to tell them apart.
    private func fetchLogging<T>(label: String, _ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            print("AppData.loadAll: fetching \(label) failed for user \(userID): \(error)")
            return nil
        }
    }

    private func refreshSignedPhotoURLs() async {
        signedPhotoURLs = await PhotoStorageService.signedURLs(for: progressPhotos.map(\.storagePath))
    }

    private func refreshAllNotifications() {
        for product in products {
            NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
        }
        NotificationManager.shared.refreshStreakReminder(usageLogs: usageLogs, restores: streakRestores)
    }

    func usageLogs(for product: Product) -> [UsageLog] {
        usageLogs.filter { $0.productID == product.id }
    }

    // MARK: - Products

    func addProduct(_ product: Product) async {
        products.append(product)
        try? await ProductService.insert(product)
    }

    func updateProduct(_ product: Product) async {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        }
        try? await ProductService.update(product)
        NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
    }

    func deleteProduct(_ product: Product) async {
        products.removeAll { $0.id == product.id }
        usageLogs.removeAll { $0.productID == product.id }
        NotificationManager.shared.cancelNotification(for: product)
        try? await ProductService.delete(id: product.id)
    }

    // MARK: - Usage logs

    /// Toggles today's usage log for a product/time-of-day: deletes it if
    /// already checked off today, otherwise creates one.
    func toggleUsageLog(for product: Product, timeOfDay: TimeOfDay) async {
        let calendar = Calendar.current
        if let existing = usageLogs.first(where: {
            $0.productID == product.id && $0.timeOfDay == timeOfDay && calendar.isDateInToday($0.timestamp)
        }) {
            usageLogs.removeAll { $0.id == existing.id }
            try? await UsageLogService.delete(id: existing.id)
        } else {
            // The product's own typical dose, not a flat number for every
            // product — see `Product.typicalDoseML` for why.
            let log = UsageLog(userID: userID, productID: product.id, timeOfDay: timeOfDay, estimatedAmountUsedML: product.typicalDoseML)
            usageLogs.append(log)
            try? await UsageLogService.insert(log)
        }
        NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
        NotificationManager.shared.refreshStreakReminder(usageLogs: usageLogs, restores: streakRestores)
        syncWidgetData()
    }

    // MARK: - Progress photos

    func addPhoto(image: UIImage, note: String? = nil) async {
        let path: String
        do {
            path = try await PhotoStorageService.upload(image: image, userID: userID)
        } catch {
            print("PhotoStorageService.upload failed: \(error)")
            photoUploadErrorMessage = "Couldn't upload photo: \(error.localizedDescription)"
            return
        }

        let photo = ProgressPhoto(userID: userID, storagePath: path, note: note)
        progressPhotos.insert(photo, at: 0)
        do {
            try await ProgressPhotoService.insert(photo)
        } catch {
            print("ProgressPhotoService.insert failed: \(error)")
            photoUploadErrorMessage = "Photo uploaded but couldn't be saved: \(error.localizedDescription)"
            progressPhotos.removeAll { $0.id == photo.id }
            return
        }
        await refreshSignedPhotoURLs()
    }

    func deletePhoto(_ photo: ProgressPhoto) async {
        progressPhotos.removeAll { $0.id == photo.id }
        signedPhotoURLs.removeValue(forKey: photo.storagePath)
        try? await ProgressPhotoService.delete(id: photo.id)
        try? await PhotoStorageService.delete(path: photo.storagePath)
    }

    /// Runs the on-device Core ML models against this photo's image and
    /// persists the resulting scores. `image` is passed in rather than
    /// re-downloaded from `signedPhotoURLs` since the caller (a detail view
    /// that's already displaying the photo) already has it decoded.
    @discardableResult
    /// Runs the on-device skin scan and persists its score. Throws so the
    /// detail view can distinguish "no face found" from other failures and
    /// say something useful instead of silently doing nothing.
    func scanPhoto(_ photo: ProgressPhoto, image: UIImage) async throws -> SkinScanResult {
        let result = try await SkinScanService.shared.scan(image)

        if let index = progressPhotos.firstIndex(where: { $0.id == photo.id }) {
            progressPhotos[index].skinScore = result.score
        }
        try? await ProgressPhotoService.updateScore(id: photo.id, score: result.score)

        let newZoneFindings = ZoneFinding.aggregate(from: result.findings, userID: userID, progressPhotoID: photo.id)
        zoneFindings.removeAll { $0.progressPhotoID == photo.id }
        zoneFindings.append(contentsOf: newZoneFindings)
        try? await ZoneFindingService.replace(forPhoto: photo.id, with: newZoneFindings)
        syncWidgetData()

        return result
    }

    // MARK: - Streak restores

    /// How often a restore may be spent. A streak you can patch without
    /// limit doesn't mean anything, so this is scarce enough that spending
    /// one is a real decision.
    static let daysBetweenStreakRestores = 30

    /// The day a restore would bridge, or nil if there's nothing worth
    /// restoring right now. See `StreakCalculator.restorableDay`.
    var restorableDay: Date? {
        StreakCalculator.restorableDay(logs: usageLogs, restores: streakRestores)
    }

    /// When the next restore becomes available, or nil if one is available
    /// now. Enforced client-side only -- this gates a cosmetic streak
    /// number, not access to data, so it isn't worth a server round trip.
    var nextStreakRestoreAvailableOn: Date? {
        guard let mostRecent = streakRestores.map(\.restoredOn).max() else { return nil }
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: Self.daysBetweenStreakRestores, to: mostRecent),
              next > calendar.startOfDay(for: .now)
        else { return nil }
        return next
    }

    var canRestoreStreak: Bool {
        isPremium && restorableDay != nil && nextStreakRestoreAvailableOn == nil
    }

    /// Spends a restore on the day that's currently breaking the streak.
    @discardableResult
    func restoreStreak() async -> Bool {
        guard canRestoreStreak, let day = restorableDay else { return false }
        let restore = StreakRestore(userID: userID, restoredOn: day)
        streakRestores.append(restore)
        do {
            try await StreakRestoreService.insert(restore)
        } catch {
            print("StreakRestoreService.insert failed: \(error)")
            streakRestores.removeAll { $0.id == restore.id }
            return false
        }
        syncWidgetData()
        return true
    }

    // MARK: - Premium

    /// Mirrors a known entitlement state into local state and Supabase.
    /// Called after a real purchase completes and by `refreshEntitlement`
    /// -- never flips this on its own. See `Profile.isPremium`.
    func setPremium(_ value: Bool) async {
        isPremium = value
        try? await ProfileService.setPremium(userID: userID, isPremium: value)
        syncWidgetData()
    }

    /// Reconciles against StoreKit's actual verified entitlement for this
    /// device -- the ground truth, since `isPremium`/Supabase are only a
    /// cache of the last thing this device (or another one, at its own
    /// last check) observed. Called from `SubscriptionService`'s live
    /// transaction listener (a real renewal/refund/Ask-to-Buy event) and
    /// from the paywall's "Restore Purchases" -- deliberately NOT from
    /// `loadAll` on every cold launch, which would silently downgrade any
    /// account back to free the moment StoreKit finds nothing (e.g. before
    /// this app's first subscription has ever cleared App Review, or on
    /// this developer's own test accounts).
    func refreshEntitlement() async {
        let hasEntitlement = await SubscriptionService.shared.hasActiveEntitlement()
        guard hasEntitlement != isPremium else { return }
        await setPremium(hasEntitlement)
    }
}
