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

    /// The routine quiz's answers (see `supabase/skin_profile.sql`). All
    /// four are nil until the quiz is taken -- which is distinct from
    /// "answered with the defaults", and is what tells the app whether it
    /// has a real profile or is falling back to conservative assumptions.
    var skinType: String?
    var skinSensitivity: String?
    var activesExperience: String?
    var routineLength: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hasCompletedOnboarding = "has_completed_onboarding"
        case isPremium = "is_premium"
        case hasUsedFreeScan = "has_used_free_scan"
        case purchasedRestoreCredits = "purchased_restore_credits"
        case skinType = "skin_type"
        case skinSensitivity = "skin_sensitivity"
        case activesExperience = "actives_experience"
        case routineLength = "routine_length"
    }

    /// Rows predating `skin_profile.sql` have none of these columns, so
    /// they decode as absent rather than failing the whole profile fetch
    /// (which would sign the user out of every premium feature at once).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        hasUsedFreeScan = try container.decodeIfPresent(Bool.self, forKey: .hasUsedFreeScan) ?? false
        purchasedRestoreCredits = try container.decodeIfPresent(Int.self, forKey: .purchasedRestoreCredits) ?? 0
        skinType = try container.decodeIfPresent(String.self, forKey: .skinType)
        skinSensitivity = try container.decodeIfPresent(String.self, forKey: .skinSensitivity)
        activesExperience = try container.decodeIfPresent(String.self, forKey: .activesExperience)
        routineLength = try container.decodeIfPresent(String.self, forKey: .routineLength)
    }

    /// The decoded quiz answers, or nil if the quiz hasn't been taken.
    /// Partial rows (one column somehow set and the others not) count as
    /// not taken -- a half-filled profile would silently mix real answers
    /// with defaults.
    var skinProfile: SkinProfile? {
        guard let skinType, let skinSensitivity, let activesExperience, let routineLength,
              let type = SkinType(rawValue: skinType),
              let sensitivity = SkinSensitivity(rawValue: skinSensitivity),
              let experience = ActivesExperience(rawValue: activesExperience),
              let length = RoutineLength(rawValue: routineLength)
        else { return nil }
        return SkinProfile(
            skinType: type,
            sensitivity: sensitivity,
            experience: experience,
            routineLength: length
        )
    }
}
