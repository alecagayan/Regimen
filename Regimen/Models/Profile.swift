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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hasCompletedOnboarding = "has_completed_onboarding"
        case isPremium = "is_premium"
    }
}
