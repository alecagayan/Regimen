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

    private let remindersEnabledKey = "remindersEnabled"

    /// User-facing toggle (see `ProfileSettingsView`). Stored in
    /// `UserDefaults` rather than synced to Supabase — it's a per-device
    /// notification preference, not routine data that needs to follow the
    /// account across devices.
    var remindersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: remindersEnabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: remindersEnabledKey)
            if !newValue {
                center.removeAllPendingNotificationRequests()
            }
        }
    }

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

        guard remindersEnabled, !product.isArchived else { return }

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

    private let streakReminderIdentifier = "streak-at-risk"
    /// Local hour to fire the reminder -- late enough that "log it later
    /// today" is still realistic, early enough to leave time before
    /// midnight actually breaks the streak.
    private let streakReminderHour = 20

    /// Reschedules (or clears) today's "don't break your streak" reminder.
    /// Same opportunistic-refresh pattern as `refreshNotification` — call
    /// this whenever usage logs change (a check-off, or a fresh
    /// `loadAll()`) rather than running a background job. A repeating
    /// notification can't be skipped conditionally once scheduled, so this
    /// always cancels first and only reschedules a fresh one-off if it's
    /// still actually needed for today.
    func refreshStreakReminder(usageLogs: [UsageLog], restores: [StreakRestore] = []) {
        center.removePendingNotificationRequests(withIdentifiers: [streakReminderIdentifier])
        guard remindersEnabled else { return }

        // Restores have to be included here too: a streak kept alive by a
        // restore is still a streak worth protecting, and computing without
        // them would read it as 0 and silently stop reminding.
        let streak = StreakCalculator.compute(from: usageLogs, restores: restores)
        // Nothing to protect (streak is 0), or today's already logged
        // (recentDays' last entry) -- either way, no reminder is useful.
        guard streak.currentStreak > 0, streak.recentDays.last == false else { return }

        let calendar = Calendar.current
        var fireComponents = calendar.dateComponents([.year, .month, .day], from: .now)
        fireComponents.hour = streakReminderHour
        fireComponents.minute = 0
        guard let fireDate = calendar.date(from: fireComponents), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak!"
        content.body = "You're on a \(streak.currentStreak)-day streak — log today's routine before it resets."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        let request = UNNotificationRequest(identifier: streakReminderIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
