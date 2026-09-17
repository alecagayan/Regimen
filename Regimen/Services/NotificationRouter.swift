//
//  NotificationRouter.swift
//  Regimen
//

import Foundation
import SwiftUI
import UserNotifications
import os

/// Where a tapped notification or widget should land.
enum AppDestination: Equatable {
    case routine(TimeOfDay?)
    case reorder
    case progress
    case cabinet

    /// Parses a `regimen://` URL. Unknown hosts route nowhere rather than
    /// guessing -- an unrecognised link should leave the app where it is,
    /// not dump the user on an arbitrary tab.
    init?(url: URL) {
        guard url.scheme == AppDeepLink.scheme, let host = url.host() else { return nil }
        switch host {
        case "routine":
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "time" }?.value
            self = .routine(raw.flatMap(TimeOfDay.init(rawValue:)))
        case "reorder": self = .reorder
        case "progress": self = .progress
        case "cabinet": self = .cabinet
        default: return nil
        }
    }
}

/// Handles notification taps and turns them into a destination.
///
/// Before this existed the app had no `UNUserNotificationCenterDelegate`
/// at all. Two consequences, both of which read as the app ignoring you:
/// tapping an evening reminder opened whatever tab you last used rather
/// than the PM routine it was reminding you about, and a notification that
/// arrived while the app was open was swallowed entirely, because
/// suppressing those is the default and only the delegate can change it.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Set when a notification is tapped, consumed and cleared by
    /// `ContentView`. A one-shot signal, like `AppNavigation.isAddingProduct`.
    var pendingDestination: AppDestination?

    /// `userInfo` key carrying the deep link a notification should open.
    static let destinationKey = "destination"

    /// Category and action identifiers for the buttons on a routine
    /// reminder. Registered once at launch; a notification whose category
    /// isn't registered simply shows no buttons, silently, so these have
    /// to match what `NotificationManager` stamps on the content.
    static let routineCategory = "routine-reminder"
    static let snoozeAction = "snooze-1h"

    /// How long "Remind me later" pushes a reminder out.
    ///
    /// An hour rather than ten minutes: the reason a routine reminder goes
    /// unactioned is almost never "I need ten more minutes", it's "not
    /// now" -- and a snooze that fires again before the situation has
    /// changed just trains people to swipe it away.
    static let snoozeInterval: TimeInterval = 3600

    private override init() { super.init() }

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.routineCategory,
                actions: [
                    UNNotificationAction(
                        identifier: Self.snoozeAction,
                        title: "Remind Me in an Hour",
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show reminders even when the app is frontmost. Silently dropping
    /// them was the default, so a user with the app open got nothing -- and
    /// "the reminder didn't fire" is indistinguishable from a broken one.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content

        // Snooze reschedules and deliberately does NOT route anywhere:
        // the user just said "not now", so opening the app on top of them
        // would be the opposite of what they asked for.
        if response.actionIdentifier == Self.snoozeAction {
            await Self.reschedule(content, after: Self.snoozeInterval)
            return
        }

        let userInfo = content.userInfo
        guard let raw = userInfo[Self.destinationKey] as? String,
              let url = URL(string: raw),
              let destination = AppDestination(url: url)
        else {
            AppLog.data.error("notification tap carried no usable destination")
            return
        }
        await MainActor.run { self.pendingDestination = destination }
    }

    /// Re-fires the same notification later. A fresh identifier each time,
    /// so snoozing twice doesn't have the second request silently replace
    /// the first and cancel it.
    private nonisolated static func reschedule(
        _ content: UNNotificationContent,
        after interval: TimeInterval
    ) async {
        let copy = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
        let request = UNNotificationRequest(
            identifier: "snoozed-\(UUID().uuidString)",
            content: copy,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.data.error("snooze failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
