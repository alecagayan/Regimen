//
//  NotificationManager.swift
//  Regimen
//

import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for scheduling depletion
/// alerts. A singleton is enough here — there's exactly one notification
/// concern in this app (reorder reminders) and one system notification
/// center, so a protocol/DI abstraction would add indirection with no
/// present benefit.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// How far before the predicted empty date to fire the reminder, so
    /// there's time to actually reorder before the product runs out.
    private let daysBeforeEmptyToNotify = 7

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func identifier(for product: Product) -> String {
        "depletion-\(product.id.uuidString)"
    }

    /// Cancels any existing depletion notification for this product and
    /// reschedules from scratch based on the current prediction. Safe to
    /// call any time usage logs change (each new log shifts the predicted
    /// empty date) without tracking whether a notification already exists —
    /// removing a nonexistent pending request is a harmless no-op.
    func refreshNotification(for product: Product, usageLogs: [UsageLog]) {
        let id = identifier(for: product)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard !product.isArchived else { return }

        let result = DepletionPredictor.predict(for: product, usageLogs: usageLogs)
        guard let emptyDate = result.predictedEmptyDate else { return }

        let calendar = Calendar.current
        guard
            let fireDate = calendar.date(byAdding: .day, value: -daysBeforeEmptyToNotify, to: emptyDate),
            fireDate > .now
        else {
            // Either already past the notify window or the product is
            // already predicted empty — nothing useful to schedule.
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(product.name) is almost empty"
        content.body = "Estimated to run out around \(Self.dateFormatter.string(from: emptyDate)). Time to reorder."
        content.sound = .default

        let fireComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelNotification(for product: Product) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: product)])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
