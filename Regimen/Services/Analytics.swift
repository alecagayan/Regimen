//
//  Analytics.swift
//  Regimen
//

import Foundation
import Supabase
import os

/// Funnel instrumentation, recorded into the app's own Postgres.
///
/// The app shipped with no tracking of any kind, which meant the
/// free-scan-to-subscription funnel -- the thing the business runs on --
/// was entirely invisible. Whether people churn at the ten-field add form,
/// at the paywall, or never scan at all was unanswerable, so every product
/// decision after it would have been a guess.
///
/// Three deliberate constraints:
///
///   - **First-party.** No SDK, no third-party collector. The App Privacy
///     label is the first place a privacy-conscious user looks, and an app
///     whose pitch is "your photos never leave the device" should not have
///     an analytics vendor on it.
///   - **Shape, not content.** A closed `Event` enum of funnel steps.
///     Nothing here carries a photo, a skin score, a product name, or free
///     text. Adding a case is a deliberate act, which is the point.
///   - **Never in the way.** Every call is fire-and-forget and every
///     failure is swallowed after logging. Analytics that can block a
///     check-off or surface an error to the user is worse than none.
@MainActor
enum Analytics {
    /// Every event the app records. Closed on purpose: a free-text
    /// `track(String)` becomes an unbounded, unreviewable set of strings
    /// within a release or two.
    enum Event {
        case onboardingStarted
        case onboardingCompleted
        case onboardingSkipped
        /// Onboarding's activation step, the single biggest drop-off risk.
        case firstProductAdded(source: ProductSource)
        case productAdded(source: ProductSource)
        case scanStarted(isFree: Bool)
        case scanCompleted(isFree: Bool)
        case scanFailed(reason: ScanFailure)
        case paywallShown(source: PaywallSource)
        case purchaseStarted(plan: String)
        case purchaseCompleted(plan: String)
        case routineCompleted(timeOfDay: String)
        case routineBuilt
        case quizCompleted

        var name: String {
            switch self {
            case .onboardingStarted: "onboarding_started"
            case .onboardingCompleted: "onboarding_completed"
            case .onboardingSkipped: "onboarding_skipped"
            case .firstProductAdded: "first_product_added"
            case .productAdded: "product_added"
            case .scanStarted: "scan_started"
            case .scanCompleted: "scan_completed"
            case .scanFailed: "scan_failed"
            case .paywallShown: "paywall_shown"
            case .purchaseStarted: "purchase_started"
            case .purchaseCompleted: "purchase_completed"
            case .routineCompleted: "routine_completed"
            case .routineBuilt: "routine_built"
            case .quizCompleted: "quiz_completed"
            }
        }

        /// Small, enumerable values only -- never anything a user typed.
        var properties: [String: String] {
            switch self {
            case .firstProductAdded(let source), .productAdded(let source):
                ["source": source.rawValue]
            case .scanStarted(let isFree), .scanCompleted(let isFree):
                ["tier": isFree ? "free" : "premium"]
            case .scanFailed(let reason):
                ["reason": reason.rawValue]
            case .paywallShown(let source):
                ["source": source.rawValue]
            case .purchaseStarted(let plan), .purchaseCompleted(let plan):
                ["plan": plan]
            case .routineCompleted(let timeOfDay):
                ["time_of_day": timeOfDay]
            default:
                [:]
            }
        }
    }

    enum ProductSource: String {
        case manual
        case catalog
        case barcode
        case routineBuilder = "routine_builder"
        case onboarding
    }

    enum PaywallSource: String {
        case scan
        case routineBuilder = "routine_builder"
        case streakRestore = "streak_restore"
        case settings
        case progressGate = "progress_gate"
    }

    enum ScanFailure: String {
        case noFace = "no_face"
        case other
    }

    private static let optOutKey = "analyticsOptOut"

    /// Opt-out rather than opt-in: the events are funnel shape on the
    /// app's own backend, not tracking across other apps, so there's no
    /// ATT prompt and no third party involved. The toggle lives in
    /// Settings and is honoured before anything is built or sent.
    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: optOutKey) }
        set { UserDefaults.standard.set(!newValue, forKey: optOutKey) }
    }

    /// Set once the user is known. Events recorded before this are
    /// dropped rather than queued -- an event with no account attached
    /// can't be inserted under the table's RLS policy anyway.
    static var userID: UUID?

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static func track(_ event: Event) {
        guard isEnabled, let userID else { return }
        let row = EventRow(
            userID: userID,
            name: event.name,
            properties: event.properties,
            appVersion: appVersion
        )
        // Detached and unawaited: nothing in the UI should ever wait on
        // this, and a failure here must not surface anywhere near the user.
        Task.detached(priority: .background) {
            do {
                try await SupabaseManager.client.from("analytics_events").insert(row).execute()
            } catch {
                AppLog.data.debug("analytics insert failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct EventRow: Encodable {
        let userID: UUID
        let name: String
        let properties: [String: String]
        let appVersion: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case name
            case properties
            case appVersion = "app_version"
        }
    }
}
