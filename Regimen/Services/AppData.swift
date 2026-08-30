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
    /// Whether this account has already spent its one free skin scan --
    /// see `Profile.hasUsedFreeScan` and `canRunFreeScan`.
    private(set) var hasUsedFreeScan = false
    /// Purchased-but-not-yet-spent streak restores -- see
    /// `Profile.purchasedRestoreCredits` and `restoreStreak`.
    private(set) var purchasedRestoreCredits = 0

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
        hasUsedFreeScan = await profileResult?.hasUsedFreeScan ?? hasUsedFreeScan
        purchasedRestoreCredits = await profileResult?.purchasedRestoreCredits ?? purchasedRestoreCredits
        zoneFindings = await zoneFindingsResult ?? []
        streakRestores = await restoresResult ?? []

        await refreshSignedPhotoURLs()
        refreshAllNotifications()
        // Needs products/usageLogs already refreshed above -- on a cold
        // launch those start out empty, and flushing against an empty
        // product list would silently drop every pending widget toggle
        // instead of reconciling it.
        await flushPendingWidgetToggles()
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
        WidgetDataStore.write(
            streak: streak,
            latestScore: latestSkinScore,
            isPremium: isPremium,
            amItems: widgetRoutineItems(for: .am),
            pmItems: widgetRoutineItems(for: .pm)
        )
    }

    /// Today's active products for one time of day, in the same order the
    /// Routine tab shows them, each carrying whether it's already been
    /// checked off today -- what the widget's interactive checklist
    /// actually displays.
    private func widgetRoutineItems(for timeOfDay: TimeOfDay) -> [WidgetRoutineItem] {
        let calendar = Calendar.current
        let filtered = products
            .filter { !$0.isArchived }
            .filter { $0.routineTime == .both || $0.routineTime.rawValue == timeOfDay.rawValue }
        return LayeringAdvisor.recommendedOrder(for: filtered).map { product in
            let isChecked = usageLogs(for: product).contains {
                $0.timeOfDay == timeOfDay && calendar.isDateInToday($0.timestamp)
            }
            return WidgetRoutineItem(id: product.id, name: product.name, icon: product.layerCategory.icon, isChecked: isChecked)
        }
    }

    /// Applies any routine check-offs made directly in the widget (see
    /// `WidgetDataStore.consumePendingToggles`) since the app was last
    /// open. Reconciles to the *intended* end state rather than blindly
    /// replaying a toggle -- `toggleUsageLog` flips whatever's currently
    /// there, and replaying a stale toggle after the state already
    /// changed some other way (say, the same item was also checked off
    /// in-app) could flip it back to the wrong value.
    private func flushPendingWidgetToggles() async {
        let pending = WidgetDataStore.consumePendingToggles()
        guard !pending.isEmpty else { return }
        let calendar = Calendar.current

        for (key, shouldBeChecked) in pending {
            let parts = key.split(separator: "|")
            guard parts.count == 2,
                  let productID = UUID(uuidString: String(parts[0])),
                  let timeOfDay = TimeOfDay(rawValue: String(parts[1])),
                  let product = products.first(where: { $0.id == productID })
            else { continue }

            let isCurrentlyChecked = usageLogs(for: product).contains {
                $0.timeOfDay == timeOfDay && calendar.isDateInToday($0.timestamp)
            }
            guard isCurrentlyChecked != shouldBeChecked else { continue }
            await toggleUsageLog(for: product, timeOfDay: timeOfDay)
        }
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

    /// True once either the free monthly restore is available or a
    /// purchased credit can cover it -- the free one is always preferred
    /// (see `restoreStreak`), so a credit only ever gets spent while
    /// genuinely on cooldown.
    var canRestoreStreak: Bool {
        guard isPremium, restorableDay != nil else { return false }
        return nextStreakRestoreAvailableOn == nil || purchasedRestoreCredits > 0
    }

    /// Spends a restore on the day that's currently breaking the streak --
    /// the free monthly one if it's available, otherwise a purchased
    /// credit. Either way the result is the same `StreakRestore` row;
    /// nothing downstream (the calendar, the streak count) needs to know
    /// which paid for it.
    @discardableResult
    func restoreStreak() async -> Bool {
        guard canRestoreStreak, let day = restorableDay else { return false }
        let spendsCredit = nextStreakRestoreAvailableOn != nil

        let restore = StreakRestore(userID: userID, restoredOn: day)
        streakRestores.append(restore)
        if spendsCredit { purchasedRestoreCredits -= 1 }

        do {
            try await StreakRestoreService.insert(restore)
        } catch {
            print("StreakRestoreService.insert failed: \(error)")
            streakRestores.removeAll { $0.id == restore.id }
            if spendsCredit { purchasedRestoreCredits += 1 }
            return false
        }

        if spendsCredit {
            try? await ProfileService.setPurchasedRestoreCredits(userID: userID, count: purchasedRestoreCredits)
        }
        syncWidgetData()
        return true
    }

    /// Buys one restore credit for $0.99 and adds it to the balance.
    @discardableResult
    func purchaseStreakRestoreCredit() async throws -> Bool {
        let purchased = try await SubscriptionService.shared.purchaseRestoreCredit()
        guard purchased else { return false }
        purchasedRestoreCredits += 1
        try? await ProfileService.setPurchasedRestoreCredits(userID: userID, count: purchasedRestoreCredits)
        return true
    }

    /// Whether this account can still run its one free scan -- premium
    /// accounts never need it, and a free account can only spend it once.
    var canRunFreeScan: Bool {
        isPremium || !hasUsedFreeScan
    }

    /// Records that the free scan has been spent. Called only after a scan
    /// actually succeeds -- a failed attempt (most commonly "no face
    /// detected") hasn't shown the user anything yet, so it shouldn't
    /// burn their one try.
    func markFreeScanUsed() async {
        guard !hasUsedFreeScan else { return }
        hasUsedFreeScan = true
        try? await ProfileService.markFreeScanUsed(userID: userID)
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
