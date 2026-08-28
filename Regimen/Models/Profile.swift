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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hasCompletedOnboarding = "has_completed_onboarding"
    }
}
