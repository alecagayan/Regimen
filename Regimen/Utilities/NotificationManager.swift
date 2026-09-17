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

    // MARK: - Routine reminders

    private let routineRemindersEnabledKey = "routineRemindersEnabled"
    private let amReminderHourKey = "amReminderHour"
    private let pmReminderHourKey = "pmReminderHour"
    private let amReminderIdentifier = "routine-reminder-am"
    private let pmReminderIdentifier = "routine-reminder-pm"

    /// Nudges at the times the user actually does their routine.
    ///
    /// Separate from `remindersEnabled`, which governs reorder and streak
    /// notifications: someone can reasonably want "you're low on cleanser"
    /// without wanting to be told to wash their face every morning. Off by
    /// default, since a daily alert nobody asked for is how an app gets its
    /// notifications turned off wholesale.
    var routineRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: routineRemindersEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: routineRemindersEnabledKey)
            if !newValue {
                center.removePendingNotificationRequests(
                    withIdentifiers: [amReminderIdentifier, pmReminderIdentifier]
                )
            }
        }
    }

    var amReminderHour: Int {
        get { UserDefaults.standard.object(forKey: amReminderHourKey) as? Int ?? 8 }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: amReminderHourKey) }
    }

    var pmReminderHour: Int {
        get { UserDefaults.standard.object(forKey: pmReminderHourKey) as? Int ?? 21 }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: pmReminderHourKey) }
    }

    /// Repeating daily reminders, rescheduled from scratch whenever the
    /// setting or the hours change.
    func refreshRoutineReminders() {
        center.removePendingNotificationRequests(
            withIdentifiers: [amReminderIdentifier, pmReminderIdentifier]
        )
        guard routineRemindersEnabled else { return }

        schedule(
            identifier: amReminderIdentifier,
            hour: amReminderHour,
            title: "Morning routine",
            body: "Time for your AM products.",
            destination: AppDeepLink.routine(timeOfDay: TimeOfDay.am.rawValue)
        )
        schedule(
            identifier: pmReminderIdentifier,
            hour: pmReminderHour,
            title: "Evening routine",
            body: "Time for your PM products.",
            destination: AppDeepLink.routine(timeOfDay: TimeOfDay.pm.rawValue)
        )
    }

    private func schedule(identifier: String, hour: Int, title: String, body: String, destination: URL?) {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Without this the tap opens whatever tab was last used, which for
        // a reminder about the evening routine is rarely the evening
        // routine. See `NotificationRouter`.
        content.userInfo = Self.routingInfo(destination)
        content.categoryIdentifier = NotificationRouter.routineCategory

        // `repeats: true` here, unlike the one-shot depletion and streak
        // reminders: this one fires every day at the same time, so there's
        // no per-day rescheduling to do.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
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
        content.userInfo = Self.routingInfo(AppDeepLink.tab("reorder"))

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
    func refreshStreakReminder(usageLogs: [UsageLog], restores: [StreakRestore] = [], products: [Product] = []) {
        center.removePendingNotificationRequests(withIdentifiers: [streakReminderIdentifier])
        guard remindersEnabled else { return }

        // Restores have to be included here too: a streak kept alive by a
        // restore is still a streak worth protecting, and computing without
        // them would read it as 0 and silently stop reminding.
        let streak = StreakCalculator.compute(from: usageLogs, restores: restores, products: products)
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
        content.body = "You're on a \(streak.currentStreak)-day streak. Log today's routine before it resets."
        content.sound = .default
        // Fires in the evening, so the PM routine is the one to open.
        content.userInfo = Self.routingInfo(AppDeepLink.routine(timeOfDay: TimeOfDay.pm.rawValue))
        content.categoryIdentifier = NotificationRouter.routineCategory

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        let request = UNNotificationRequest(identifier: streakReminderIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// `userInfo` payload naming where a tap should land. Empty when the
    /// URL couldn't be built, which routes nowhere rather than to a wrong
    /// guess.
    private static func routingInfo(_ destination: URL?) -> [String: Any] {
        guard let destination else { return [:] }
        return [NotificationRouter.destinationKey: destination.absoluteString]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
