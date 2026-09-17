//
//  AppData.swift
//  Regimen
//

import Foundation
import UIKit
import os

/// Single in-memory source of truth for the signed-in user's products,
/// usage logs, and progress photos, loaded from Supabase and mutated
/// optimistically (update local state immediately, write to Supabase in the
/// background) so the UI feels instant.
///
/// Supabase Postgres remains the only authoritative store. What sits in
/// front of it is deliberately modest and one-directional:
///
/// - `LocalCache` keeps the last good snapshot on disk, so a cold launch
///   with no network shows the user's routine instead of an empty app.
/// - `PendingWriteQueue` parks check-offs that failed to send and retries
///   them, because a silently-dropped check-off used to reappear as a
///   *lost* one on the next fetch.
///
/// That's not a general offline sync engine -- there's no conflict
/// resolution, and only usage logs are queued. It is enough for the case
/// that actually happens: someone doing their routine somewhere with bad
/// signal.
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
    /// Days the user marked their skin as reacting -- see `SkinReaction`.
    private(set) var reactions: [SkinReaction] = []
    /// Finished bottles, kept after the product may be gone.
    private(set) var empties: [ProductEmpty] = []
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
    /// The routine quiz's answers as stored on the account, or nil if it
    /// hasn't been taken. See `supabase/skin_profile.sql`.
    private(set) var skinProfile: SkinProfile?
    /// True while the UI is showing the on-disk snapshot because a fetch
    /// couldn't complete -- drives the offline banner.
    private(set) var isShowingCachedData = false
    /// Set when a deliberate, user-initiated write fails, so the UI can say
    /// so instead of pretending it worked. Cleared by the view that shows it.
    var lastWriteError: String?

    /// Check-offs written to disk but not yet accepted by the server.
    private var pendingWrites: [PendingWrite] = []
    /// Whether anything is still waiting to sync -- shown in the banner so
    /// "your streak is safe, it just hasn't uploaded" is visible rather
    /// than assumed.
    var hasUnsyncedChanges: Bool { !pendingWrites.isEmpty }

    private var lastSuccessfulLoad: Date?
    private var signedURLsMintedAt: Date?
    /// In-flight debounced cache write -- see `saveCache`.
    private var cacheSaveTask: Task<Void, Never>?

    /// Why a load is happening. Foreground loads are debounced; an explicit
    /// one (sign-in, pull to refresh) always refetches.
    enum LoadTrigger {
        case explicit
        case foreground
    }

    /// Minimum gap between full refetches triggered by the app merely
    /// coming forward. Without this, every glance at the app-switcher fired
    /// six queries and re-minted every signed photo URL.
    private static let foregroundRefreshInterval: TimeInterval = 60

    /// Signed photo URLs last an hour (see `PhotoStorageService`); re-mint
    /// with a margin so a photo can't blank out mid-session.
    private static let signedURLRefreshInterval: TimeInterval = 45 * 60

    let userID: UUID

    init(userID: UUID) {
        self.userID = userID
        Analytics.userID = userID
        pendingWrites = PendingWriteQueue.load(userID: userID)
        // Show last session's data immediately, before any network call --
        // the alternative is an empty app for however long the first fetch
        // takes, or forever if it never succeeds.
        if let cached = LocalCache.load(userID: userID) {
            apply(cached)
            isShowingCachedData = true
        }
        SubscriptionService.shared.onEntitlementChanged = { [weak self] in
            await self?.refreshEntitlement()
        }
    }

    private func apply(_ snapshot: CachedSnapshot) {
        // Same layering as `loadAll`: the disk cache was written before the
        // queued work happened, so replaying the outbox over it is what
        // makes an offline edit survive a cold launch.
        products = PendingWriteQueue.apply(pendingWrites, toProducts: snapshot.products)
        usageLogs = PendingWriteQueue.apply(pendingWrites, toLogs: snapshot.usageLogs)
        progressPhotos = snapshot.progressPhotos
        zoneFindings = snapshot.zoneFindings
        streakRestores = snapshot.streakRestores
        reactions = PendingWriteQueue.apply(pendingWrites, toReactions: snapshot.reactions)
        empties = PendingWriteQueue.apply(pendingWrites, toEmpties: snapshot.empties)
        isPremium = snapshot.isPremium
        hasUsedFreeScan = snapshot.hasUsedFreeScan
        purchasedRestoreCredits = snapshot.purchasedRestoreCredits
    }

    /// Schedules a cache write, coalescing bursts.
    ///
    /// Called after every mutation, including each individual check-off --
    /// so a user ticking off five products in a row would otherwise encode
    /// and write their entire history five times. Building the snapshot
    /// here is cheap (arrays are copy-on-write); the encode happens off the
    /// main actor inside `LocalCache.save`.
    private func saveCache() {
        let snapshot = CachedSnapshot(
            products: products,
            usageLogs: usageLogs,
            progressPhotos: progressPhotos,
            zoneFindings: zoneFindings,
            streakRestores: streakRestores,
            reactions: reactions,
            empties: empties,
            isPremium: isPremium,
            hasUsedFreeScan: hasUsedFreeScan,
            purchasedRestoreCredits: purchasedRestoreCredits,
            savedAt: .now
        )
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [userID] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await LocalCache.save(snapshot, userID: userID)
        }
    }

    /// Drops everything this device has stored for the account. Called on
    /// sign-out -- leaving one person's products and skin scores on disk
    /// for whoever signs in next would be a real leak.
    func clearLocalData() {
        LocalCache.clear(userID: userID)
        PendingWriteQueue.clear(userID: userID)
        pendingWrites = []
    }

    func loadAll(trigger: LoadTrigger = .explicit) async {
        // A foreground refresh that's already fresh still has cheap work
        // worth doing: widget check-offs to reconcile, queued writes to
        // retry, and photo URLs that may have aged out. Just not six
        // queries and a full re-mint.
        if trigger == .foreground,
           let lastSuccessfulLoad,
           Date.now.timeIntervalSince(lastSuccessfulLoad) < Self.foregroundRefreshInterval {
            await refreshSignedPhotoURLsIfStale()
            await flushPendingWidgetToggles()
            await flushPendingWrites()
            syncWidgetData()
            return
        }

        isLoading = true
        defer { isLoading = false }

        async let productsResult = fetchLogging(label: "products") { try await ProductService.fetchAll(userID: self.userID) }
        async let logsResult = fetchLogging(label: "usage logs") { try await UsageLogService.fetchAll(userID: self.userID) }
        async let photosResult = fetchLogging(label: "progress photos") { try await ProgressPhotoService.fetchAll(userID: self.userID) }
        async let profileResult = fetchLogging(label: "profile") { try await ProfileService.fetch(userID: self.userID) }
        async let zoneFindingsResult = fetchLogging(label: "zone findings") { try await ZoneFindingService.fetchAll(userID: self.userID) }
        async let restoresResult = fetchLogging(label: "streak restores") { try await StreakRestoreService.fetchAll(userID: self.userID) }
        async let reactionsResult = fetchLogging(label: "reactions") { try await SkinReactionService.fetchAll(userID: self.userID) }
        async let emptiesResult = fetchLogging(label: "empties") { try await ProductEmptyService.fetchAll(userID: self.userID) }

        let fetchedProducts = await productsResult
        let fetchedLogs = await logsResult
        let fetchedPhotos = await photosResult
        let fetchedProfile = await profileResult
        let fetchedZoneFindings = await zoneFindingsResult
        let fetchedRestores = await restoresResult
        let fetchedReactions = await reactionsResult
        let fetchedEmpties = await emptiesResult

        // Keep what's already loaded when a fetch fails, rather than
        // assigning `?? []`. That old default meant one dropped request
        // emptied the user's cabinet on screen -- indistinguishable, to
        // them, from having lost their data.
        // Every list the outbox can touch gets the same treatment as
        // usage logs below: server rows first, queued work layered back on
        // top. Without this the refetch visibly undoes anything authored
        // offline -- the product reappears as deleted, the reaction
        // vanishes -- which is exactly the bug the queue exists to prevent.
        if let fetchedProducts { products = PendingWriteQueue.apply(pendingWrites, toProducts: fetchedProducts) }
        if let fetchedPhotos { progressPhotos = fetchedPhotos }
        if let fetchedZoneFindings { zoneFindings = fetchedZoneFindings }
        if let fetchedRestores { streakRestores = fetchedRestores }
        if let fetchedReactions { reactions = PendingWriteQueue.apply(pendingWrites, toReactions: fetchedReactions) }
        if let fetchedEmpties { empties = PendingWriteQueue.apply(pendingWrites, toEmpties: fetchedEmpties) }
        if let fetchedProfile {
            isPremium = fetchedProfile.isPremium
            hasUsedFreeScan = fetchedProfile.hasUsedFreeScan
            purchasedRestoreCredits = fetchedProfile.purchasedRestoreCredits
            skinProfile = fetchedProfile.skinProfile
        }
        if let fetchedLogs {
            // Server rows first, then anything still queued layered back on
            // top -- otherwise this fetch would visibly un-check a box the
            // user ticked while offline.
            usageLogs = PendingWriteQueue.apply(pendingWrites, toLogs: fetchedLogs)
        }

        // Reactions and empties count too. Leaving them out meant a
        // permanent decode failure in either one was completely invisible:
        // the banner cleared, the app looked healthy, and those features
        // stayed silently empty forever.
        let everythingLoaded = fetchedProducts != nil && fetchedLogs != nil && fetchedPhotos != nil
            && fetchedProfile != nil && fetchedZoneFindings != nil && fetchedRestores != nil
            && fetchedReactions != nil && fetchedEmpties != nil
        isShowingCachedData = !everythingLoaded
        if everythingLoaded { lastSuccessfulLoad = .now }

        // Needs products/usageLogs already refreshed above -- on a cold
        // launch those start out empty, and flushing against an empty
        // product list would silently drop every pending widget toggle
        // instead of reconciling it.
        await flushPendingWidgetToggles()
        await flushPendingWrites()

        await refreshSignedPhotoURLs()
        refreshAllNotifications()
        syncWidgetData()
        saveCache()
    }

    /// Retries everything in the outbox and persists whatever's left.
    private func flushPendingWrites() async {
        guard !pendingWrites.isEmpty else { return }
        let remaining = await PendingWriteQueue.flush(pendingWrites)
        pendingWrites = remaining
        PendingWriteQueue.save(remaining, userID: userID)
    }

    /// Sends one write now, or queues it if the send fails.
    ///
    /// Anything already queued takes precedence: these are ordered
    /// operations against the same rows, and letting a new write overtake a
    /// stalled one could apply a delete before its own insert.
    private func performOrQueue(_ write: PendingWrite) async {
        if pendingWrites.isEmpty {
            do {
                try await PendingWriteQueue.send(write)
                return
            } catch {
                AppLog.sync.error("write failed, queuing: \(error.localizedDescription, privacy: .public)")
            }
        }
        pendingWrites.append(write)
        PendingWriteQueue.save(pendingWrites, userID: userID)
    }

    /// Runs a user-initiated write, reporting failure instead of
    /// swallowing it. Returns whether it succeeded so the caller can roll
    /// back its optimistic local change.
    @discardableResult
    private func write(_ description: String, _ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            return true
        } catch {
            AppLog.data.error("\(description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            lastWriteError = NetworkMonitor.shared.isOnline
                ? "Couldn't \(description). Please try again."
                : "Couldn't \(description). You appear to be offline."
            return false
        }
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
        let streak = StreakCalculator.compute(from: usageLogs, restores: streakRestores, products: products).currentStreak
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
            // Only what's actually due today -- a thrice-weekly retinoid
            // shouldn't sit unchecked on the widget the other four days.
            .filter { $0.isScheduled(on: .now) }
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
            AppLog.data.error("loadAll: fetching \(label, privacy: .public) failed for user \(self.userID.uuidString, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Mints signed URLs for both the photos and any stored scan overlays.
    private func refreshSignedPhotoURLs() async {
        let paths = progressPhotos.map(\.storagePath) + progressPhotos.compactMap(\.overlayPath)
        signedPhotoURLs = await PhotoStorageService.signedURLs(for: paths)
        signedURLsMintedAt = .now
    }

    /// Re-mints only once the current batch is close to expiring. These
    /// URLs live an hour and used to be refreshed solely inside a full
    /// `loadAll`, so a session left open past the hour turned every photo
    /// into a grey rectangle with no way back short of relaunching.
    private func refreshSignedPhotoURLsIfStale() async {
        guard let signedURLsMintedAt else {
            await refreshSignedPhotoURLs()
            return
        }
        guard Date.now.timeIntervalSince(signedURLsMintedAt) > Self.signedURLRefreshInterval else { return }
        await refreshSignedPhotoURLs()
    }

    private func refreshAllNotifications() {
        for product in products {
            NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
        }
        NotificationManager.shared.refreshStreakReminder(usageLogs: usageLogs, restores: streakRestores, products: products)
    }

    func usageLogs(for product: Product) -> [UsageLog] {
        usageLogs.filter { $0.productID == product.id }
    }

    // MARK: - Products

    /// Products aren't queued the way check-offs are: adding one is a
    /// deliberate foreground action with a form attached, so a failure is
    /// rolled back and reported rather than left on screen as a row that
    /// doesn't exist anywhere and will vanish at the next refresh.
    func addProduct(_ product: Product, source: Analytics.ProductSource = .manual) async {
        products.append(product)
        // Queued rather than rolled back: adding a product is exactly the
        // thing someone does standing in a shop with one bar of signal,
        // and losing it there means retyping the whole form later.
        await performOrQueue(.insertProduct(product))
        // "First" is judged against the cabinet, not a stored flag: this is
        // the activation moment onboarding is trying to reach.
        let isFirst = products.filter { !$0.isArchived }.count == 1
        Analytics.track(isFirst ? .firstProductAdded(source: source) : .productAdded(source: source))
        saveCache()
    }

    func updateProduct(_ product: Product) async {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        }
        await performOrQueue(.updateProduct(product))
        NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
        saveCache()
    }

    func deleteProduct(_ product: Product) async {
        products.removeAll { $0.id == product.id }
        usageLogs.removeAll { $0.productID == product.id }
        NotificationManager.shared.cancelNotification(for: product)

        // The server cascades the logs from the product row's deletion, so
        // only the product itself needs sending.
        await performOrQueue(.deleteProduct(id: product.id))
        saveCache()
    }

    // MARK: - Usage logs

    /// Toggles today's usage log for a product/time-of-day: deletes it if
    /// already checked off today, otherwise creates one.
    func toggleUsageLog(for product: Product, timeOfDay: TimeOfDay) async {
        await toggleUsageLog(for: product, timeOfDay: timeOfDay, on: .now)
    }

    /// Whether a product is checked off for a given day and time.
    func isLogged(_ product: Product, timeOfDay: TimeOfDay, on day: Date) -> Bool {
        let calendar = Calendar.current
        return usageLogs.contains {
            $0.productID == product.id
                && $0.timeOfDay == timeOfDay
                && calendar.isDate($0.timestamp, inSameDayAs: day)
        }
    }

    /// Checks off everything not already done, for one time of day.
    /// For someone who did their whole routine before opening the app,
    /// ticking six boxes one at a time is busywork.
    func checkOffAll(_ products: [Product], timeOfDay: TimeOfDay, on day: Date = .now) async {
        for product in products where !isLogged(product, timeOfDay: timeOfDay, on: day) {
            await toggleUsageLog(for: product, timeOfDay: timeOfDay, on: day)
        }
    }

    /// Logs against an arbitrary day, so a routine that was actually done
    /// but never logged can be recorded after the fact.
    ///
    /// Forgetting to *log* is a different failure from skipping the
    /// routine, and the app previously treated them identically -- a missed
    /// tap broke the streak with a paid restore as the only remedy. The UI
    /// limits this to the previous day (see `RoutineView`); going further
    /// back stops being a correction and starts being fiction.
    func toggleUsageLog(for product: Product, timeOfDay: TimeOfDay, on day: Date) async {
        let calendar = Calendar.current
        if let existing = usageLogs.first(where: {
            $0.productID == product.id && $0.timeOfDay == timeOfDay && calendar.isDate($0.timestamp, inSameDayAs: day)
        }) {
            usageLogs.removeAll { $0.id == existing.id }
            await performOrQueue(.deleteUsageLog(id: existing.id))
        } else {
            // The product's own typical dose, not a flat number for every
            // product — see `Product.typicalDoseML` for why.
            // Timestamped noon on the target day rather than `.now`, so a
            // backfilled log lands unambiguously inside that calendar day
            // regardless of the reader's timezone.
            let timestamp = calendar.isDateInToday(day)
                ? Date.now
                : (calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
            let log = UsageLog(
                userID: userID,
                productID: product.id,
                timestamp: timestamp,
                timeOfDay: timeOfDay,
                estimatedAmountUsedML: product.typicalDoseML
            )
            usageLogs.append(log)
            await performOrQueue(.insertUsageLog(log))
        }
        NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
        NotificationManager.shared.refreshStreakReminder(usageLogs: usageLogs, restores: streakRestores, products: products)
        syncWidgetData()
        saveCache()
    }

    // MARK: - Progress photos

    /// Returns the stored photo on success, so the caller can take the user
    /// straight to it -- adding a photo and then having to hunt for its
    /// info button to actually scan it made the app's main feature two
    /// discoveries deep. Nil means the upload or the insert failed and
    /// `photoUploadErrorMessage` has been set.
    @discardableResult
    func addPhoto(image: UIImage, note: String? = nil) async -> ProgressPhoto? {
        let path: String
        do {
            path = try await PhotoStorageService.upload(image: image, userID: userID)
        } catch {
            AppLog.storage.error("photo upload failed: \(error.localizedDescription, privacy: .public)")
            photoUploadErrorMessage = "Couldn't upload photo: \(error.localizedDescription)"
            return nil
        }

        let photo = ProgressPhoto(userID: userID, storagePath: path, note: note)
        progressPhotos.insert(photo, at: 0)
        do {
            try await ProgressPhotoService.insert(photo)
        } catch {
            AppLog.data.error("progress photo insert failed: \(error.localizedDescription, privacy: .public)")
            photoUploadErrorMessage = "Photo uploaded but couldn't be saved: \(error.localizedDescription)"
            progressPhotos.removeAll { $0.id == photo.id }
            return nil
        }
        // Signed URL first: the detail view the caller is about to present
        // loads the image from `signedPhotoURLs`, and handing it a photo
        // whose URL hasn't been minted yet shows an empty grey frame.
        await refreshSignedPhotoURLs()
        return photo
    }

    func deletePhoto(_ photo: ProgressPhoto) async {
        progressPhotos.removeAll { $0.id == photo.id }
        signedPhotoURLs.removeValue(forKey: photo.storagePath)
        // Postgres cascades `zone_findings` from the photo row, but local
        // state doesn't cascade itself -- without this the deleted scan's
        // per-zone rows sat in memory and got written straight back into
        // the on-disk cache, surviving until the next full fetch.
        zoneFindings.removeAll { $0.progressPhotoID == photo.id }
        if let overlayPath = photo.overlayPath {
            signedPhotoURLs.removeValue(forKey: overlayPath)
        }
        await write("delete this photo") { try await ProgressPhotoService.delete(id: photo.id) }
        try? await PhotoStorageService.delete(path: photo.storagePath)
        // Best-effort: an orphaned overlay costs a few KB, and failing the
        // whole delete over it would leave the photo itself half-removed.
        if let overlayPath = photo.overlayPath {
            try? await PhotoStorageService.delete(path: overlayPath)
        }
        saveCache()
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

        // Store the rendered highlights alongside the photo so reopening it
        // shows the scan again. Best-effort: if the upload fails the score
        // and findings are still worth saving, the photo just won't redraw
        // its overlay until it's scanned again.
        var overlayPath: String?
        if let overlay = result.overlay {
            do {
                overlayPath = try await PhotoStorageService.uploadOverlay(
                    image: overlay,
                    userID: userID,
                    photoID: photo.id
                )
            } catch {
                AppLog.storage.error("overlay upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let index = progressPhotos.firstIndex(where: { $0.id == photo.id }) {
            progressPhotos[index].skinScore = result.score
            progressPhotos[index].skinAttributeKeys = result.attributes.map(\.persistenceKey)
            progressPhotos[index].overlayPath = overlayPath
            progressPhotos[index].faceRectX = result.faceRect.minX
            progressPhotos[index].faceRectY = result.faceRect.minY
            progressPhotos[index].faceRectWidth = result.faceRect.width
            progressPhotos[index].faceRectHeight = result.faceRect.height
        }

        await write("save this scan") {
            try await ProgressPhotoService.updateScan(
                id: photo.id,
                update: ProgressPhotoService.ScanUpdate(
                    skinScore: result.score,
                    skinAttributes: result.attributes.map(\.persistenceKey),
                    overlayPath: overlayPath,
                    faceRectX: result.faceRect.minX,
                    faceRectY: result.faceRect.minY,
                    faceRectWidth: result.faceRect.width,
                    faceRectHeight: result.faceRect.height
                )
            )
        }

        let newZoneFindings = ZoneFinding.aggregate(from: result.findings, userID: userID, progressPhotoID: photo.id)
        zoneFindings.removeAll { $0.progressPhotoID == photo.id }
        zoneFindings.append(contentsOf: newZoneFindings)
        await write("save this scan's zones") {
            try await ZoneFindingService.replace(forPhoto: photo.id, with: newZoneFindings)
        }

        // Mints a URL for the overlay just uploaded, so the stored version
        // is displayable without waiting for the next full load.
        await refreshSignedPhotoURLs()
        syncWidgetData()
        saveCache()

        return result
    }

    /// Attaches (or clears) a note on a progress photo.
    ///
    /// `ProgressPhoto.note` existed in the model and in Postgres from the
    /// start and was never once written or read -- a timeline of faces with
    /// no way to record "started tretinoin" or "bad sleep week" beside
    /// them, which is most of what makes a timeline mean anything later.
    func setNote(_ note: String?, on photo: ProgressPhoto) async {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let index = progressPhotos.firstIndex(where: { $0.id == photo.id }) {
            progressPhotos[index].note = stored
        }
        await performOrQueue(.setPhotoNote(id: photo.id, note: stored))
        saveCache()
    }

    /// The per-kind finding counts stored for a photo, rebuilt from
    /// `zone_findings`. Lets an already-scanned photo show its "SPOTTED"
    /// list without re-running the models -- which a free account, having
    /// spent its one scan, cannot do at all.
    func storedFindingCounts(for photo: ProgressPhoto) -> [FindingKind: Int] {
        zoneFindings
            .filter { $0.progressPhotoID == photo.id }
            .reduce(into: [:]) { counts, finding in
                counts[finding.kind, default: 0] += finding.findingCount
            }
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
            AppLog.data.error("streak restore insert failed: \(error.localizedDescription, privacy: .public)")
            streakRestores.removeAll { $0.id == restore.id }
            if spendsCredit { purchasedRestoreCredits += 1 }
            return false
        }

        if spendsCredit {
            await write("save your restore balance") {
                try await ProfileService.setPurchasedRestoreCredits(userID: self.userID, count: self.purchasedRestoreCredits)
            }
        }
        syncWidgetData()
        saveCache()
        return true
    }

    /// Buys one restore credit for $0.99 and adds it to the balance.
    @discardableResult
    func purchaseStreakRestoreCredit() async throws -> Bool {
        let purchased = try await SubscriptionService.shared.purchaseRestoreCredit()
        guard purchased else { return false }
        purchasedRestoreCredits += 1
        await write("save your restore balance") {
            try await ProfileService.setPurchasedRestoreCredits(userID: self.userID, count: self.purchasedRestoreCredits)
        }
        saveCache()
        return true
    }

    // MARK: - Reactions

    func reaction(on day: Date) -> SkinReaction? {
        let calendar = Calendar.current
        return reactions.first { calendar.isDate($0.occurredOn, inSameDayAs: day) }
    }

    /// Records (or corrects) a bad-skin day. One row per day, so marking
    /// the same day again updates it.
    func setReaction(severity: ReactionSeverity, note: String?, on day: Date = .now) async {
        let existing = reaction(on: day)
        let reaction = SkinReaction(
            id: existing?.id ?? UUID(),
            userID: userID,
            occurredOn: day,
            severity: severity,
            note: note
        )
        reactions.removeAll { $0.id == reaction.id }
        reactions.append(reaction)
        await performOrQueue(.saveReaction(reaction))
        saveCache()
    }

    func clearReaction(on day: Date) async {
        guard let existing = reaction(on: day) else { return }
        reactions.removeAll { $0.id == existing.id }
        await performOrQueue(.deleteReaction(id: existing.id))
        saveCache()
    }

    // MARK: - Empties

    /// Archives a finished product and keeps a record of how it went.
    /// Archiving rather than deleting: the usage history behind it is what
    /// the streak and every prediction are built from.
    func recordEmpty(
        for product: Product,
        wouldRepurchase: Bool?,
        rating: Int?,
        note: String?
    ) async {
        let empty = ProductEmpty(
            userID: userID,
            productID: product.id,
            productName: product.name,
            brand: product.brand,
            wouldRepurchase: wouldRepurchase,
            rating: rating,
            note: note
        )
        empties.insert(empty, at: 0)
        await performOrQueue(.insertEmpty(empty))

        var archived = product
        archived.isArchived = true
        await updateProduct(archived)
    }

    /// Everything this account holds, for `DataExportService`.
    func exportSnapshot() -> DataExportService.Export {
        DataExportService.Export(
            exportedAt: .now,
            skinProfile: skinProfile,
            products: products,
            usageLogs: usageLogs,
            progressPhotos: progressPhotos,
            // Signed links rather than the JPEGs themselves: the bytes
            // would dwarf the JSON, but a bare storage path is useless to
            // anyone outside the app, so the export would have been a list
            // of photos you couldn't actually retrieve.
            photoDownloads: signedPhotoURLs.reduce(into: [:]) { result, entry in
                result[entry.key] = entry.value.absoluteString
            },
            photoDownloadsExpireAt: signedURLsMintedAt.map {
                $0.addingTimeInterval(PhotoStorageService.signedURLLifetimeInterval)
            },
            zoneFindings: zoneFindings,
            streakRestores: streakRestores,
            reactions: reactions,
            empties: empties
        )
    }

    // MARK: - Skin profile

    /// Persists the routine quiz's answers to the account, so the same
    /// person gets the same advice on every device. The UserDefaults copy
    /// is kept as a local mirror: it's what personalizes the very first
    /// screen after a cold, offline launch, before any profile fetch lands.
    func saveSkinProfile(_ profile: SkinProfile) async {
        skinProfile = profile
        profile.save()
        await performOrQueue(.setSkinProfile(userID: userID, profile: profile))
    }

    /// What the recommendation and routine engines should personalize
    /// against: the account's stored answers when the quiz has been taken,
    /// this device's last local copy otherwise, and `SkinProfile`'s
    /// deliberately cautious defaults if neither exists.
    var effectiveSkinProfile: SkinProfile {
        skinProfile ?? SkinProfile.load()
    }

    /// Whether the quiz has ever been answered -- used to offer it rather
    /// than silently personalizing against defaults the user never chose.
    var hasSkinProfile: Bool { skinProfile != nil }

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
        await write("record your free scan") { try await ProfileService.markFreeScanUsed(userID: self.userID) }
        saveCache()
    }

    // MARK: - Premium

    /// Mirrors a known entitlement state into local state and Supabase.
    /// Called after a real purchase completes and by `refreshEntitlement`
    /// -- never flips this on its own. See `Profile.isPremium`.
    func setPremium(_ value: Bool) async {
        isPremium = value
        await write("update your subscription status") {
            try await ProfileService.setPremium(userID: self.userID, isPremium: value)
        }
        syncWidgetData()
        saveCache()
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
