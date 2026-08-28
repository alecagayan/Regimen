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
    /// storagePath -> a signed URL valid for the lifetime set in
    /// `PhotoStorageService`. Refreshed on every `loadAll()`.
    private(set) var signedPhotoURLs: [String: URL] = [:]
    private(set) var isLoading = false

    let userID: UUID

    init(userID: UUID) {
        self.userID = userID
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        async let productsResult = try? ProductService.fetchAll(userID: userID)
        async let logsResult = try? UsageLogService.fetchAll(userID: userID)
        async let photosResult = try? ProgressPhotoService.fetchAll(userID: userID)

        products = await productsResult ?? []
        usageLogs = await logsResult ?? []
        progressPhotos = await photosResult ?? []

        await refreshSignedPhotoURLs()
        refreshAllNotifications()
    }

    private func refreshSignedPhotoURLs() async {
        signedPhotoURLs = await PhotoStorageService.signedURLs(for: progressPhotos.map(\.storagePath))
    }

    private func refreshAllNotifications() {
        for product in products {
            NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
        }
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
            // A fixed per-application estimate — see `UsageLog` for why.
            let log = UsageLog(userID: userID, productID: product.id, timeOfDay: timeOfDay, estimatedAmountUsedML: 0.5)
            usageLogs.append(log)
            try? await UsageLogService.insert(log)
        }
        NotificationManager.shared.refreshNotification(for: product, usageLogs: usageLogs(for: product))
    }

    // MARK: - Progress photos

    func addPhoto(image: UIImage, note: String? = nil) async {
        guard let path = try? await PhotoStorageService.upload(image: image, userID: userID) else { return }
        let photo = ProgressPhoto(userID: userID, storagePath: path, note: note)
        progressPhotos.insert(photo, at: 0)
        try? await ProgressPhotoService.insert(photo)
        await refreshSignedPhotoURLs()
    }

    func deletePhoto(_ photo: ProgressPhoto) async {
        progressPhotos.removeAll { $0.id == photo.id }
        signedPhotoURLs.removeValue(forKey: photo.storagePath)
        try? await ProgressPhotoService.delete(id: photo.id)
        try? await PhotoStorageService.delete(path: photo.storagePath)
    }
}
