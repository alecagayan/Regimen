//
//  Profile.swift
//  Regimen
//

import Foundation

/// Maps 1:1 to the `profiles` table. A row is created automatically (via a
/// Postgres trigger — see `supabase/schema.sql`) whenever someone signs up,
/// pulling `name` out of the signup metadata. `hasCompletedOnboarding` is
/// what gates the one-time onboarding pane after account creation.
struct Profile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var hasCompletedOnboarding: Bool
    /// Gates every premium feature (see `PaywallView`). A cache of
    /// StoreKit's real per-device entitlement (see `SubscriptionService`
    /// and `AppData.refreshEntitlement`), not itself the source of truth --
    /// kept here so other devices/views can read it without an async
    /// StoreKit round trip.
    var isPremium: Bool
    /// Whether this account has already spent its one free skin scan (see
    /// `AppData.canRunFreeScan`). Stored server-side, same reasoning as
    /// `isPremium` -- an on-device flag could just be cleared by
    /// reinstalling the app.
    var hasUsedFreeScan: Bool
    /// Purchased-but-not-yet-spent streak restores, bought as a $0.99
    /// consumable -- a way past the free one-every-30-days limit without
    /// waiting. See `AppData.restoreStreak`.
    var purchasedRestoreCredits: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hasCompletedOnboarding = "has_completed_onboarding"
        case isPremium = "is_premium"
        case hasUsedFreeScan = "has_used_free_scan"
        case purchasedRestoreCredits = "purchased_restore_credits"
    }
}
