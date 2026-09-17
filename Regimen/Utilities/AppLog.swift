//
//  AppLog.swift
//  Regimen
//

import Foundation
import os

/// The app's loggers, one per subsystem area.
///
/// `print` writes to stdout unconditionally -- it ships compiled into
/// release builds, can't be filtered or disabled, and has no notion of
/// sensitivity, which is how user IDs and auth session state ended up in
/// the device console on every launch. `os.Logger` fixes all three: it's
/// free when nothing is listening, filterable by subsystem/category in
/// Console.app, and redacts interpolated strings in release builds unless
/// they're explicitly marked `.public`.
///
/// Rule of thumb for this app: anything identifying a *person* (user ID,
/// email, product names they typed) is `.private`; model diagnostics and
/// error descriptions are fine as-is.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.alecagayan.Regimen"

    /// Fetching and mutating the user's own rows.
    static let data = Logger(subsystem: subsystem, category: "data")
    /// Sign-in, session restore, token refresh.
    static let auth = Logger(subsystem: subsystem, category: "auth")
    /// On-device Core ML inference.
    static let scan = Logger(subsystem: subsystem, category: "scan")
    /// Photo upload/download and signed URLs.
    static let storage = Logger(subsystem: subsystem, category: "storage")
    /// StoreKit.
    static let purchases = Logger(subsystem: subsystem, category: "purchases")
    /// The offline cache and the pending-write outbox.
    static let sync = Logger(subsystem: subsystem, category: "sync")
}
